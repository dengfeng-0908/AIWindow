import Foundation

protocol AIHotServing {
    func fetchItems(
        query: AIHotItemsQuery,
        cursor: String?
    ) async throws -> AIHotItemsResponse

    func fetchHotTopics() async throws -> AIHotTopicsResponse

    func fetchLatestDaily() async throws -> AIHotDailyResponse
}

struct AIHotClient: AIHotServing {
    static let productionBaseURL = URL(string: "https://aihot.virxact.com")!

    private let baseURL: URL
    private let session: URLSession
    private let responseCache: AIHotResponseCache

    init(
        baseURL: URL = AIHotClient.productionBaseURL,
        session: URLSession = .shared,
        responseCache: AIHotResponseCache = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.responseCache = responseCache
    }

    func fetchItems(
        query: AIHotItemsQuery,
        cursor: String? = nil
    ) async throws -> AIHotItemsResponse {
        try await send(makeItemsRequest(query: query, cursor: cursor))
    }

    func fetchHotTopics() async throws -> AIHotTopicsResponse {
        try await send(makeRequest(path: "/api/v1/hot-topics"))
    }

    func fetchLatestDaily() async throws -> AIHotDailyResponse {
        try await send(makeRequest(path: "/api/v1/dailies/latest"))
    }

    func makeItemsRequest(
        query: AIHotItemsQuery,
        cursor: String? = nil
    ) throws -> URLRequest {
        guard (1...100).contains(query.limit) else {
            throw AIHotClientError.invalidLimit
        }

        if let searchText = query.normalizedSearchText,
           !(2...200).contains(searchText.count) {
            throw AIHotClientError.invalidSearchLength
        }

        var queryItems = [
            URLQueryItem(name: "mode", value: "selected"),
            URLQueryItem(name: "window", value: query.window.rawValue),
            URLQueryItem(name: "by", value: "timeline"),
            URLQueryItem(name: "limit", value: String(query.limit)),
        ]

        if let category = query.category.apiValue {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let searchText = query.normalizedSearchText {
            queryItems.append(URLQueryItem(name: "q", value: searchText))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return makeRequest(path: "/api/v1/items", queryItems: queryItems)
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIWindow-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send<Response: Decodable>(
        _ request: URLRequest
    ) async throws -> Response {
        do {
            let plan = await responseCache.plan(for: request)
            switch plan {
            case let .cached(data):
                return try decode(data)
            case let .throttled(retryAfter):
                throw AIHotClientError.requestThrottled(retryAfter: retryAfter)
            case let .network(networkRequest, cachedData):
                return try await performNetworkRequest(
                    networkRequest,
                    cachedData: cachedData
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIHotClientError {
            throw error
        } catch let error as URLError {
            throw AIHotClientError.transport(error.code)
        } catch {
            throw AIHotClientError.transport(.unknown)
        }
    }

    private func performNetworkRequest<Response: Decodable>(
        _ request: URLRequest,
        cachedData: Data?
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHotClientError.invalidResponse
        }

        if httpResponse.statusCode == 304 {
            guard let revalidatedData = await responseCache.revalidatedData(
                for: request,
                response: httpResponse
            ) ?? cachedData else {
                throw AIHotClientError.invalidResponse
            }
            return try decode(revalidatedData)
        }

        let retryAfter = AIHotRetryAfter.seconds(
            from: httpResponse.value(forHTTPHeaderField: "Retry-After")
        )
        if [429, 503].contains(httpResponse.statusCode), let retryAfter {
            await responseCache.deferRequest(
                for: request,
                retryAfter: retryAfter
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let problem = try? AIHotJSON.decoder().decode(AIHotProblem.self, from: data)
            throw AIHotClientError.http(
                status: httpResponse.statusCode,
                detail: problem?.detail,
                retryAfter: retryAfter
            )
        }

        let decoded: Response = try decode(data)
        await responseCache.store(data, response: httpResponse, for: request)
        return decoded
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try AIHotJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw AIHotClientError.invalidData
        }
    }
}

enum AIHotRequestPlan: Sendable {
    case cached(Data)
    case throttled(retryAfter: Int)
    case network(URLRequest, cachedData: Data?)
}

actor AIHotResponseCache {
    static let shared = AIHotResponseCache()
    static let minimumRequestInterval: TimeInterval = 60
    static let maximumEntryCount = 128

    private struct Entry: Sendable {
        var data: Data
        var entityTag: String?
        var lastModified: String?
        var validatedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var nextAllowedDates: [String: Date] = [:]

    func plan(
        for request: URLRequest,
        at now: Date = .now
    ) -> AIHotRequestPlan {
        pruneExpiredRequestDates(at: now)
        guard let key = request.url?.absoluteString else {
            return .network(request, cachedData: nil)
        }

        if let nextAllowedDate = nextAllowedDates[key], nextAllowedDate > now {
            if let entry = entries[key] {
                return .cached(entry.data)
            }
            return .throttled(
                retryAfter: Self.seconds(until: nextAllowedDate, from: now)
            )
        }

        nextAllowedDates[key] = now.addingTimeInterval(Self.minimumRequestInterval)

        guard let entry = entries[key] else {
            return .network(request, cachedData: nil)
        }

        var conditionalRequest = request
        if let entityTag = entry.entityTag {
            conditionalRequest.setValue(entityTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = entry.lastModified {
            conditionalRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return .network(conditionalRequest, cachedData: entry.data)
    }

    func store(
        _ data: Data,
        response: HTTPURLResponse,
        for request: URLRequest,
        at now: Date = .now
    ) {
        guard let key = request.url?.absoluteString else { return }

        entries[key] = Entry(
            data: data,
            entityTag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
            validatedAt: now
        )
        trimEntriesIfNeeded()
        extendMinimumInterval(for: key, from: now)
    }

    func revalidatedData(
        for request: URLRequest,
        response: HTTPURLResponse,
        at now: Date = .now
    ) -> Data? {
        guard let key = request.url?.absoluteString,
              var entry = entries[key] else {
            return nil
        }

        entry.entityTag = response.value(forHTTPHeaderField: "ETag") ?? entry.entityTag
        entry.lastModified = response.value(forHTTPHeaderField: "Last-Modified")
            ?? entry.lastModified
        entry.validatedAt = now
        entries[key] = entry
        extendMinimumInterval(for: key, from: now)
        return entry.data
    }

    func deferRequest(
        for request: URLRequest,
        retryAfter: Int,
        at now: Date = .now
    ) {
        guard retryAfter > 0,
              let key = request.url?.absoluteString else {
            return
        }

        let serverDate = now.addingTimeInterval(TimeInterval(retryAfter))
        nextAllowedDates[key] = max(nextAllowedDates[key] ?? .distantPast, serverDate)
    }

    private func extendMinimumInterval(for key: String, from date: Date) {
        let minimumDate = date.addingTimeInterval(Self.minimumRequestInterval)
        nextAllowedDates[key] = max(nextAllowedDates[key] ?? .distantPast, minimumDate)
    }

    private func pruneExpiredRequestDates(at now: Date) {
        nextAllowedDates = nextAllowedDates.filter { key, date in
            entries[key] != nil || date > now
        }
    }

    private func trimEntriesIfNeeded() {
        while entries.count > Self.maximumEntryCount,
              let oldestKey = entries.min(by: {
                  $0.value.validatedAt < $1.value.validatedAt
              })?.key {
            entries.removeValue(forKey: oldestKey)
        }
    }

    private static func seconds(until date: Date, from now: Date) -> Int {
        max(1, Int(ceil(date.timeIntervalSince(now))))
    }
}

enum AIHotRetryAfter {
    static func seconds(
        from value: String?,
        now: Date = .now
    ) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let seconds = Int(value), seconds > 0 {
            return seconds
        }

        for format in httpDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) {
                let interval = Int(ceil(date.timeIntervalSince(now)))
                return interval > 0 ? interval : nil
            }
        }
        return nil
    }

    private static let httpDateFormats = [
        "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
        "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
        "EEE MMM d HH':'mm':'ss yyyy",
    ]
}

enum AIHotClientError: LocalizedError {
    case invalidLimit
    case invalidSearchLength
    case invalidResponse
    case invalidData
    case requestThrottled(retryAfter: Int)
    case http(status: Int, detail: String?, retryAfter: Int?)
    case transport(URLError.Code)

    var errorDescription: String? {
        switch self {
        case .invalidLimit:
            return "每次加载的资讯数量无效。"
        case .invalidSearchLength:
            return "搜索词需要包含 2 到 200 个字符。"
        case .invalidResponse:
            return "AI HOT 返回了无效响应，请稍后重试。"
        case .invalidData:
            return "AI HOT 返回了暂时无法识别的数据，请稍后重试。"
        case let .requestThrottled(retryAfter):
            return retryMessage(
                prefix: "相同内容的刷新间隔至少为 60 秒",
                retryAfter: retryAfter
            )
        case let .http(status, _, retryAfter):
            switch status {
            case 400:
                return "筛选条件无效，请调整后重试。"
            case 403:
                return "AI HOT 暂时拒绝了此请求，请稍后重试。"
            case 404:
                return "当前没有可用的 AI HOT 内容。"
            case 429:
                return retryMessage(
                    prefix: "请求过于频繁",
                    retryAfter: retryAfter
                )
            case 503:
                return retryMessage(
                    prefix: "AI HOT 服务暂时不可用",
                    retryAfter: retryAfter
                )
            default:
                return "AI HOT 请求失败（HTTP \(status)）。"
            }
        case let .transport(code):
            switch code {
            case .notConnectedToInternet:
                return "网络未连接，请检查网络后重试。"
            case .timedOut:
                return "连接 AI HOT 超时，请稍后重试。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "暂时无法连接 AI HOT，请稍后重试。"
            default:
                return "网络请求失败，请稍后重试。"
            }
        }
    }

    private func retryMessage(prefix: String, retryAfter: Int?) -> String {
        guard let retryAfter else {
            return "\(prefix)，请稍后重试。"
        }
        return "\(prefix)，请等待约 \(retryAfter) 秒后重试。"
    }
}

private struct AIHotProblem: Decodable {
    let detail: String
}

enum AIHotJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: value)
                ?? internetFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date"
            )
        }
        return decoder
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
