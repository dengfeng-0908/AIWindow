import Combine
import Foundation
import SwiftData
import UIKit
import WebKit

enum BrowserSessionPolicy: Equatable {
    case ephemeralSearch
    case persistentLinuxDO

    static func policy(for initialURL: URL) -> Self {
        if TopicURLNormalizer.isAllowedInAppURL(initialURL),
           TopicURLNormalizer.isLinuxDOURL(initialURL) {
            return .persistentLinuxDO
        }
        return .ephemeralSearch
    }

    var usesPersistentWebsiteData: Bool {
        self == .persistentLinuxDO
    }

    func shouldRouteToPersistentSession(_ url: URL) -> Bool {
        self == .ephemeralSearch
            && TopicURLNormalizer.isAllowedInAppURL(url)
            && TopicURLNormalizer.isLinuxDOURL(url)
    }

    func allowsTopLevelNavigation(to url: URL) -> Bool {
        switch self {
        case .ephemeralSearch:
            return TopicURLNormalizer.isAllowedInAppURL(url)
                && !TopicURLNormalizer.isLinuxDOURL(url)
        case .persistentLinuxDO:
            return TopicURLNormalizer.isAllowedInAppURL(url)
                && TopicURLNormalizer.isLinuxDOURL(url)
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

@MainActor
final class BrowserViewModel: NSObject, ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = "浏览"
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isCurrentTopicFavorite = false
    @Published private(set) var pendingPersistentURL: URL?
    @Published var errorMessage: String?

    let webView: WKWebView
    let sessionPolicy: BrowserSessionPolicy

    private let initialURL: URL
    private let modelContext: ModelContext
    private var hasLoadedInitialURL = false
    private var lastRecordedCanonicalURL: String?
    private var currentTopic: TopicRecord?

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
    }

    func loadInitialURLIfNeeded() {
        guard !hasLoadedInitialURL else { return }
        hasLoadedInitialURL = true
        guard TopicURLNormalizer.isAllowedInAppURL(initialURL) else {
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

    func clearPendingPersistentNavigation() {
        pendingPersistentURL = nil
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
                return
            }

            currentTopic = try TopicRepository.recordVisit(
                url: url,
                title: webView.title,
                in: modelContext
            )
            lastRecordedCanonicalURL = canonicalString
            isCurrentTopicFavorite = currentTopic?.isFavorite ?? false
        } catch {
            errorMessage = "无法保存浏览记录：\(error.localizedDescription)"
        }
    }
}

extension BrowserViewModel: WKNavigationDelegate {
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
                pendingPersistentURL = url
                decisionHandler(.cancel)
                return
            }

            guard sessionPolicy.allowsTopLevelNavigation(to: url) else {
                if TopicURLNormalizer.isSafeExternalURL(url) {
                    UIApplication.shared.open(url)
                }
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
        pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "浏览"
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
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        errorMessage = "页面加载失败：\(error.localizedDescription)"
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
            pendingPersistentURL = url
        } else if sessionPolicy.allowsTopLevelNavigation(to: url) {
            webView.load(URLRequest(url: url))
        } else if TopicURLNormalizer.isSafeExternalURL(url) {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
