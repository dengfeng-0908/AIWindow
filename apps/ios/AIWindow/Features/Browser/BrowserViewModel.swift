import Combine
import Foundation
import SwiftData
import UIKit
import WebKit

enum BrowserSessionPolicy: Equatable {
    case ephemeralSearch
    case persistentLinuxDO
    case ephemeralExternal

    static func policy(for initialURL: URL) -> Self {
        if TopicURLNormalizer.isAllowedInAppURL(initialURL),
           TopicURLNormalizer.isLinuxDOURL(initialURL) {
            return .persistentLinuxDO
        }
        if TopicURLNormalizer.isAllowedInAppURL(initialURL) {
            return .ephemeralSearch
        }
        if TopicURLNormalizer.isSafeEphemeralInAppURL(initialURL) {
            return .ephemeralExternal
        }
        return .ephemeralSearch
    }

    var usesPersistentWebsiteData: Bool {
        self == .persistentLinuxDO
    }

    func shouldRouteToPersistentSession(_ url: URL) -> Bool {
        self != .persistentLinuxDO
            && TopicURLNormalizer.isAllowedInAppURL(url)
            && TopicURLNormalizer.isLinuxDOURL(url)
    }

    func shouldRouteToIsolatedSession(_ url: URL) -> Bool {
        self != .ephemeralExternal
            && TopicURLNormalizer.isSafeEphemeralInAppURL(url)
            && !TopicURLNormalizer.isLinuxDOURL(url)
            && !allowsTopLevelNavigation(to: url)
    }

    func allowsTopLevelNavigation(to url: URL) -> Bool {
        switch self {
        case .ephemeralSearch:
            return TopicURLNormalizer.isAllowedInAppURL(url)
                && !TopicURLNormalizer.isLinuxDOURL(url)
        case .persistentLinuxDO:
            return TopicURLNormalizer.isAllowedInAppURL(url)
                && TopicURLNormalizer.isLinuxDOURL(url)
        case .ephemeralExternal:
            return TopicURLNormalizer.isSafeEphemeralInAppURL(url)
                && !TopicURLNormalizer.isLinuxDOURL(url)
        }
    }
}

enum BrowserWebsiteDataController {
    static let dataDidClearNotification = Notification.Name(
        "AIWindowLinuxDOWebsiteDataDidClear"
    )

    static func clearPersistentData(completion: @escaping @MainActor () -> Void) {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            Task { @MainActor in
                NotificationCenter.default.post(name: dataDidClearNotification, object: nil)
                completion()
            }
        }
    }
}

enum BrowserNavigationResponsePolicy {
    static func linuxDOSearchErrorMessage(
        for url: URL,
        statusCode: Int,
        mimeType: String?
    ) -> String? {
        let normalizedPath = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard TopicURLNormalizer.isLinuxDOURL(url), normalizedPath == "search" else {
            return nil
        }

        switch statusCode {
        case 401, 403:
            return "LINUX DO 当前未允许此会话访问搜索。请先打开站内首页完成登录，或返回使用外部搜索。"
        case 429:
            return "LINUX DO 搜索请求过于频繁，请稍后再试，或返回使用外部搜索。"
        case 400...599:
            return "LINUX DO 搜索暂时不可用，请稍后再试，或返回使用外部搜索。"
        default:
            let normalizedMIMEType = mimeType?
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedMIMEType == "application/json"
                ? "LINUX DO 搜索暂时不可用，请稍后再试，或返回使用外部搜索。"
                : nil
        }
    }
}

enum BrowserNavigationErrorPolicy {
    private static let networkStateErrorCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
    ]

    static func message(
        for error: Error,
        sessionPolicy: BrowserSessionPolicy
    ) -> String? {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return nil
        }

        if sessionPolicy == .persistentLinuxDO,
           nsError.domain == NSURLErrorDomain,
           networkStateErrorCodes.contains(nsError.code) {
            return "LINUX DO 页面暂时无法连接。请先检查网络；如果你刚开启或切换代理，请在 App 切换器中结束“AI 视窗”，再重新打开。登录状态会保留。"
        }

        return "页面加载失败：\(error.localizedDescription)"
    }
}

private struct ForumTopicMetadata: Decodable {
    let title: String
    let canonicalURL: String
}

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = "浏览"
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isCurrentTopicFavorite = false
    @Published private(set) var pendingInAppURL: URL?
    @Published private(set) var isPreparingAnalysis = false
    @Published private(set) var analysisContext: TopicAnalysisContext?
    @Published var errorMessage: String?

    let webView: WKWebView
    let sessionPolicy: BrowserSessionPolicy

    private let initialURL: URL
    private let modelContext: ModelContext
    private var hasLoadedInitialURL = false
    private var lastRecordedCanonicalURL: String?
    private var currentTopic: TopicRecord?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var observedNavigationTask: Task<Void, Never>?
    private var titleRefreshTask: Task<Void, Never>?

    init(initialURL: URL, modelContext: ModelContext) {
        self.initialURL = initialURL
        self.modelContext = modelContext
        sessionPolicy = BrowserSessionPolicy.policy(for: initialURL)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sessionPolicy.usesPersistentWebsiteData
            ? .default()
            : .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleObservedNavigationChange()
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updatePageTitle()
                self?.refreshCurrentTopicTitleIfNeeded()
            }
        }
    }

    deinit {
        observedNavigationTask?.cancel()
        titleRefreshTask?.cancel()
        urlObservation?.invalidate()
        titleObservation?.invalidate()
    }

    func loadInitialURLIfNeeded() {
        guard !hasLoadedInitialURL else { return }
        hasLoadedInitialURL = true
        guard sessionPolicy.allowsTopLevelNavigation(to: initialURL) else {
            errorMessage = "该地址不能在 App 内打开。"
            return
        }
        webView.load(URLRequest(url: initialURL))
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func clearPendingInAppNavigation() {
        pendingInAppURL = nil
    }

    func clearAnalysisContext() {
        analysisContext = nil
    }

    func reloadAfterWebsiteDataClear() {
        guard sessionPolicy == .persistentLinuxDO else { return }
        webView.stopLoading()
        webView.load(URLRequest(url: currentURL ?? initialURL))
    }

    func openInDefaultBrowser() {
        guard let currentURL,
              TopicURLNormalizer.isSafeExternalURL(currentURL) else {
            return
        }
        UIApplication.shared.open(currentURL)
    }

    func copyLink() {
        guard let currentURL else { return }
        UIPasteboard.general.url = currentURL
    }

    var canAnalyzeCurrentTopic: Bool {
        guard let currentURL else { return false }
        return TopicURLNormalizer.canonicalTopicURL(from: currentURL) != nil
    }

    func prepareCurrentTopicAnalysis() {
        guard !isPreparingAnalysis,
              let currentURL,
              let canonicalURL = TopicURLNormalizer.canonicalTopicURL(from: currentURL)
        else {
            return
        }

        isPreparingAnalysis = true
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isPreparingAnalysis = false }
            do {
                let rawValue = try await webView.evaluateJavaScript(Self.topicExtractionScript)
                guard let json = rawValue as? String,
                      let data = json.data(using: .utf8)
                else {
                    throw TopicAnalysisContextError.noReadableContent
                }
                let snapshot = try JSONDecoder().decode(ForumPageSnapshot.self, from: data)
                analysisContext = try TopicAnalysisContextBuilder.make(
                    title: snapshot.title,
                    canonicalURL: canonicalURL,
                    candidates: snapshot.posts
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleFavorite() {
        guard let topic = currentTopic else { return }
        do {
            try TopicRepository.setFavorite(!topic.isFavorite, for: topic, in: modelContext)
            isCurrentTopicFavorite = topic.isFavorite
        } catch {
            errorMessage = "无法更新收藏：\(error.localizedDescription)"
        }
    }

    private func updateNavigationState() {
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private func updatePageTitle() {
        pageTitle = webView.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "浏览"
    }

    private func handleObservedNavigationChange() {
        updateNavigationState()
        observedNavigationTask?.cancel()
        observedNavigationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            updatePageTitle()
            updateNavigationState()
            recordCurrentTopicIfNeeded()
        }
    }

    private func recordCurrentTopicIfNeeded() {
        guard let url = webView.url,
              let canonicalURL = TopicURLNormalizer.canonicalTopicURL(from: url)
        else {
            currentTopic = nil
            isCurrentTopicFavorite = false
            lastRecordedCanonicalURL = nil
            return
        }

        let canonicalString = canonicalURL.absoluteString
        do {
            if canonicalString == lastRecordedCanonicalURL,
               let existing = try TopicRepository.topic(for: canonicalString, in: modelContext) {
                currentTopic = existing
                isCurrentTopicFavorite = existing.isFavorite
                refreshCurrentTopicTitle(for: canonicalURL)
                return
            }

            currentTopic = try TopicRepository.recordVisit(
                url: url,
                title: webView.title,
                in: modelContext
            )
            lastRecordedCanonicalURL = canonicalString
            isCurrentTopicFavorite = currentTopic?.isFavorite ?? false
            refreshCurrentTopicTitle(for: canonicalURL)
        } catch {
            errorMessage = "无法保存浏览记录：\(error.localizedDescription)"
        }
    }

    private func refreshCurrentTopicTitleIfNeeded() {
        guard let url = webView.url,
              let canonicalURL = TopicURLNormalizer.canonicalTopicURL(from: url) else {
            return
        }
        refreshCurrentTopicTitle(for: canonicalURL)
    }

    private func refreshCurrentTopicTitle(for canonicalURL: URL) {
        titleRefreshTask?.cancel()
        titleRefreshTask = Task { [weak self] in
            guard let self else { return }

            for delay in [
                UInt64(0),
                400_000_000,
                1_200_000_000,
                2_400_000_000,
                4_000_000_000
            ] {
                if delay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: delay)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled,
                      let currentURL = webView.url,
                      TopicURLNormalizer.canonicalTopicURL(from: currentURL) == canonicalURL else {
                    return
                }

                do {
                    let rawValue = try await webView.evaluateJavaScript(
                        Self.topicMetadataExtractionScript
                    )
                    guard let json = rawValue as? String,
                          let data = json.data(using: .utf8),
                          let metadata = try? JSONDecoder().decode(
                              ForumTopicMetadata.self,
                              from: data
                          ),
                          let metadataURL = URL(string: metadata.canonicalURL),
                          TopicURLNormalizer.canonicalTopicURL(from: metadataURL) == canonicalURL,
                          !TopicTitleNormalizer.isFallback(
                              TopicTitleNormalizer.normalized(
                                  metadata.title,
                                  fallbackURL: canonicalURL
                              ),
                              for: canonicalURL
                          ),
                          let topic = try TopicRepository.topic(
                              for: canonicalURL.absoluteString,
                              in: modelContext
                          ) else {
                        continue
                    }

                    try TopicRepository.updateTitle(
                        metadata.title,
                        for: topic,
                        in: modelContext
                    )
                    currentTopic = topic
                    pageTitle = topic.displayTitle
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private static let topicMetadataExtractionScript = #"""
    (() => {
        const normalize = (value) => String(value || "")
            .replace(/\u00a0/g, " ")
            .replace(/[ \t]+/g, " ")
            .replace(/\n{2,}/g, " ")
            .trim();
        const canonicalNode = document.querySelector("link[rel='canonical']");
        const titleNode = document.querySelector(
            "h1#topic-title, #topic-title h1, .fancy-title, .topic-title h1"
        );
        const metadataTitle = document.querySelector("meta[property='og:title']")
            ?.getAttribute("content");
        return JSON.stringify({
            title: normalize(titleNode ? titleNode.innerText : metadataTitle).slice(0, 500),
            canonicalURL: canonicalNode ? canonicalNode.href : ""
        });
    })();
    """#

    private static let topicExtractionScript = #"""
    (() => {
        const normalize = (value) => String(value || "")
            .replace(/\u00a0/g, " ")
            .replace(/[ \t]+/g, " ")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
        const articles = Array.from(document.querySelectorAll("article[data-post-id]"));
        const nodes = articles.length > 0
            ? articles
            : Array.from(document.querySelectorAll(".topic-post"));
        const viewportCenter = window.innerHeight / 2;
        const posts = nodes.slice(0, 100).map((node, index) => {
            const body = node.querySelector(".cooked, [itemprop='articleBody']");
            const numberedNode = node.hasAttribute("data-post-number")
                ? node
                : node.querySelector("[data-post-number]");
            const parsedOrder = Number.parseInt(
                numberedNode ? numberedNode.getAttribute("data-post-number") : "",
                10
            );
            const rect = node.getBoundingClientRect();
            return {
                order: Number.isFinite(parsedOrder) ? parsedOrder : index + 1,
                text: normalize(body ? body.innerText : "").slice(0, 12000),
                distanceFromViewport: Math.abs(rect.top + rect.height / 2 - viewportCenter)
            };
        }).filter((post) => post.text.length > 0);
        const titleNode = document.querySelector(
            "h1#topic-title, #topic-title h1, .fancy-title, .topic-title h1"
        );
        const metadataTitle = document.querySelector("meta[property='og:title']")
            ?.getAttribute("content");
        return JSON.stringify({
            title: normalize(titleNode ? titleNode.innerText : metadataTitle).slice(0, 500),
            posts
        });
    })();
    """#
}

extension BrowserViewModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url,
              let message = BrowserNavigationResponsePolicy.linuxDOSearchErrorMessage(
                  for: url,
                  statusCode: response.statusCode,
                  mimeType: response.mimeType
              )
        else {
            decisionHandler(.allow)
            return
        }

        isLoading = false
        errorMessage = message
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard url.scheme == "http" || url.scheme == "https" else {
            if isMainFrame && TopicURLNormalizer.isSafeExternalURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        if isMainFrame {
            if sessionPolicy.shouldRouteToPersistentSession(url) {
                pendingInAppURL = url
                decisionHandler(.cancel)
                return
            }

            if sessionPolicy.shouldRouteToIsolatedSession(url) {
                pendingInAppURL = url
                decisionHandler(.cancel)
                return
            }

            guard sessionPolicy.allowsTopLevelNavigation(to: url) else {
                errorMessage = "该链接不能在 App 内安全打开。"
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        isLoading = true
        errorMessage = nil
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoading = false
        updatePageTitle()
        updateNavigationState()
        recordCurrentTopicIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        isLoading = false
        errorMessage = BrowserNavigationErrorPolicy.message(
            for: error,
            sessionPolicy: sessionPolicy
        )
        updateNavigationState()
    }
}

extension BrowserViewModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url
        else {
            return nil
        }

        if sessionPolicy.shouldRouteToPersistentSession(url) {
            pendingInAppURL = url
        } else if sessionPolicy.shouldRouteToIsolatedSession(url) {
            pendingInAppURL = url
        } else if sessionPolicy.allowsTopLevelNavigation(to: url) {
            webView.load(URLRequest(url: url))
        } else {
            errorMessage = "该链接不能在 App 内安全打开。"
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
