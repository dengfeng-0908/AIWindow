import Foundation
import SwiftData
import XCTest
@testable import AIWindow

@MainActor
final class AIWindowTests: XCTestCase {
    func testCanonicalTopicURLRemovesPostNumberQueryAndFragment() {
        let input = URL(
            string: "https://www.linux.do/t/a-useful-topic/12345/8?utm_source=test#reply"
        )!

        let result = TopicURLNormalizer.canonicalTopicURL(from: input)

        XCTAssertEqual(result?.absoluteString, "https://linux.do/t/a-useful-topic/12345")
    }

    func testCanonicalTopicURLRejectsLookalikeHostAndNonTopicPage() {
        XCTAssertNil(
            TopicURLNormalizer.canonicalTopicURL(
                from: URL(string: "https://linux.do.example.com/t/topic/123")!
            )
        )
        XCTAssertNil(
            TopicURLNormalizer.canonicalTopicURL(
                from: URL(string: "https://linux.do/categories")!
            )
        )
    }

    func testCanonicalTopicURLRequiresExpectedTopicIDPositionAndNoCredentials() {
        XCTAssertNil(
            TopicURLNormalizer.canonicalTopicURL(
                from: URL(string: "https://linux.do/t/example/not-an-id/12345")!
            )
        )
        XCTAssertNil(
            TopicURLNormalizer.canonicalTopicURL(
                from: credentialBearingURL(host: "linux.do", path: "/t/example/123")
            )
        )
    }

    func testTopicRecordDoesNotExposeUnsafeStoredURL() {
        let record = TopicRecord(
            canonicalURL: "javascript:alert(1)",
            title: "Unsafe"
        )

        XCTAssertNil(record.url)
    }

    func testInAppBrowserRequiresHTTPSAndApprovedHost() {
        XCTAssertTrue(
            TopicURLNormalizer.isAllowedInAppURL(
                URL(string: "https://search.bing.com/results")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isAllowedInAppURL(
                URL(string: "http://linux.do/t/example/123")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isAllowedInAppURL(
                URL(string: "https://linux.do.example.com/t/example/123")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isAllowedInAppURL(
                credentialBearingURL(host: "linux.do", path: "/t/example/123")
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isAllowedInAppURL(
                URL(string: "https://linux.do:444/t/example/123")!
            )
        )
    }

    func testExternalURLAllowlistRejectsCustomSchemes() {
        XCTAssertTrue(
            TopicURLNormalizer.isSafeExternalURL(
                URL(string: "tel:+123456789")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isSafeExternalURL(
                URL(string: "untrusted-app://linux.do/action")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isSafeExternalURL(
                URL(string: "javascript:alert(1)")!
            )
        )
        XCTAssertFalse(
            TopicURLNormalizer.isSafeExternalURL(
                credentialBearingURL(host: "example.com", path: "/private")
            )
        )
    }

    func testLinuxDOPagesUsePersistentSessionWhileSearchPagesRemainEphemeral() {
        XCTAssertEqual(
            BrowserSessionPolicy.policy(
                for: URL(string: "https://linux.do/t/example/123")!
            ),
            .persistentLinuxDO
        )
        XCTAssertEqual(
            BrowserSessionPolicy.policy(
                for: URL(string: "https://www.bing.com/search?q=linux.do")!
            ),
            .ephemeralSearch
        )
        XCTAssertEqual(
            BrowserSessionPolicy.policy(
                for: URL(string: "http://linux.do/t/example/123")!
            ),
            .ephemeralSearch
        )
        XCTAssertTrue(BrowserSessionPolicy.persistentLinuxDO.usesPersistentWebsiteData)
        XCTAssertFalse(BrowserSessionPolicy.ephemeralSearch.usesPersistentWebsiteData)
    }

    func testSearchSessionRoutesOnlyApprovedLinuxDOURLsToPersistentSession() {
        let policy = BrowserSessionPolicy.ephemeralSearch

        XCTAssertTrue(
            policy.shouldRouteToPersistentSession(
                URL(string: "https://linux.do/t/example/123")!
            )
        )
        XCTAssertFalse(
            policy.shouldRouteToPersistentSession(
                URL(string: "https://linux.do.example.com/t/example/123")!
            )
        )
        XCTAssertFalse(
            policy.shouldRouteToPersistentSession(
                URL(string: "http://linux.do/t/example/123")!
            )
        )
    }

    func testPersistentSessionKeepsSearchEnginesOutOfPersistentDataStore() {
        let policy = BrowserSessionPolicy.persistentLinuxDO

        XCTAssertTrue(
            policy.allowsTopLevelNavigation(
                to: URL(string: "https://linux.do/categories")!
            )
        )
        XCTAssertFalse(
            policy.allowsTopLevelNavigation(
                to: URL(string: "https://www.google.com/search?q=linux.do")!
            )
        )

        XCTAssertTrue(
            BrowserSessionPolicy.ephemeralSearch.allowsTopLevelNavigation(
                to: URL(string: "https://www.google.com/search?q=linux.do")!
            )
        )
        XCTAssertFalse(
            BrowserSessionPolicy.ephemeralSearch.allowsTopLevelNavigation(
                to: URL(string: "https://linux.do/t/example/123")!
            )
        )
    }

    func testSearchURLUsesSiteRestrictionAndSelectedEngine() {
        let url = SearchEngine.bing.searchURL(for: "Swift 数据库")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems?.first(where: { $0.name == "q" })?.value

        XCTAssertEqual(url.host, "www.bing.com")
        XCTAssertEqual(query, "site:linux.do/t/topic Swift 数据库")
    }

    func testRepeatedSearchUpdatesExistingHistoryEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = SearchViewModel()
        viewModel.query = "SwiftData"
        viewModel.engine = .bing
        XCTAssertNotNil(viewModel.makeSearchURL(in: context))

        viewModel.query = "SwiftData"
        XCTAssertNotNil(viewModel.makeSearchURL(in: context))

        let records = try context.fetch(FetchDescriptor<SearchRecord>())
        XCTAssertEqual(records.count, 1)
    }

    func testRepeatedVisitUpdatesOneTopic() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstURL = URL(string: "https://linux.do/t/example/9876")!
        let replyURL = URL(string: "https://linux.do/t/example/9876/4?x=1")!

        try TopicRepository.recordVisit(url: firstURL, title: "Example", in: context)
        try TopicRepository.recordVisit(url: replyURL, title: "Example - LINUX DO", in: context)

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics[0].visitCount, 2)
        XCTAssertEqual(topics[0].title, "Example")
    }

    func testRemovingFavoriteHistoryPreservesFavorite() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let topic = try XCTUnwrap(
            TopicRepository.recordVisit(
                url: URL(string: "https://linux.do/t/example/2468")!,
                title: "Example",
                in: context
            )
        )
        try TopicRepository.setFavorite(true, for: topic, in: context)

        try TopicRepository.removeFromHistory(topic, in: context)

        XCTAssertTrue(topic.isFavorite)
        XCTAssertFalse(topic.hasHistory)
        XCTAssertEqual(topic.visitCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TopicRecord>()).count, 1)
    }

    func testBackupImportIsIdempotent() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let topic = try XCTUnwrap(
            TopicRepository.recordVisit(
                url: URL(string: "https://linux.do/t/backup/1357")!,
                title: "Backup",
                in: sourceContext
            )
        )
        try TopicRepository.setFavorite(true, for: topic, in: sourceContext)
        topic.note = "保留备注"
        topic.tags = ["Swift", "iOS"]
        sourceContext.insert(SearchRecord(query: "Swift", engine: .bing))
        try sourceContext.save()

        let payload = BackupService.makePayload(
            topics: try sourceContext.fetch(FetchDescriptor<TopicRecord>()),
            searches: try sourceContext.fetch(FetchDescriptor<SearchRecord>())
        )
        let decoded = try BackupService.decode(BackupService.encode(payload))

        let destination = try makeContainer()
        let destinationContext = destination.mainContext
        _ = try BackupService.merge(decoded, into: destinationContext)
        _ = try BackupService.merge(decoded, into: destinationContext)

        let importedTopics = try destinationContext.fetch(FetchDescriptor<TopicRecord>())
        let importedSearches = try destinationContext.fetch(FetchDescriptor<SearchRecord>())
        XCTAssertEqual(importedTopics.count, 1)
        XCTAssertEqual(importedTopics[0].note, "保留备注")
        XCTAssertEqual(Set(importedTopics[0].tags), Set(["Swift", "iOS"]))
        XCTAssertEqual(importedSearches.count, 1)
    }

    func testBackupRejectsOversizedDocumentBeforeDecoding() {
        let data = Data(count: BackupService.maximumDocumentBytes + 1)

        XCTAssertThrowsError(try BackupService.decode(data)) { error in
            guard case BackupError.documentTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testBackupRejectsOversizedRecordField() throws {
        let payload = BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            exportedAt: .now,
            topics: [],
            searches: [
                SearchBackup(
                    id: UUID(),
                    query: String(repeating: "x", count: 10_001),
                    engine: .bing,
                    searchedAt: .now
                ),
            ]
        )

        XCTAssertThrowsError(
            try BackupService.decode(BackupService.encode(payload))
        ) { error in
            guard case BackupError.invalidDocument = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAIHotItemsResponseDecodesV1ContractAndUnknownCategory() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "query": {
                "mode": "selected",
                "category": null,
                "window": "7d",
                "q": null,
                "by": "timeline",
                "ordering": "timelineDesc"
              },
              "items": [
                {
                  "id": "item-1",
                  "title": "一条 AI 资讯",
                  "originalTitle": null,
                  "summary": "中文摘要",
                  "source": { "name": "Example News" },
                  "links": {
                    "aihot": "https://aihot.virxact.com/items/item-1",
                    "original": "https://example.com/news/item-1"
                  },
                  "publishedAt": "2026-07-25T01:08:45.000Z",
                  "discoveredAt": "2026-07-25T01:10:00.123Z",
                  "category": "future-category",
                  "score": 88.5,
                  "selected": true,
                  "attribution": {
                    "name": "AI HOT",
                    "url": "https://aihot.virxact.com/items/item-1"
                  }
                }
              ],
              "page": { "count": 1, "hasMore": false, "nextCursor": null }
            }
            """#.utf8
        )

        let response = try AIHotJSON.decoder().decode(AIHotItemsResponse.self, from: data)

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.items.first?.id, "item-1")
        XCTAssertEqual(response.items.first?.categoryName, "其他")
        XCTAssertEqual(response.items.first?.source.name, "Example News")
        XCTAssertEqual(
            response.items.first?.links.original.absoluteString,
            "https://example.com/news/item-1"
        )
    }

    func testAIHotLinksRejectNonWebOriginalURL() {
        let data = Data(
            #"{"aihot":"https://aihot.virxact.com/items/1","original":"javascript:alert(1)"}"#.utf8
        )

        XCTAssertThrowsError(
            try AIHotJSON.decoder().decode(AIHotContentLinks.self, from: data)
        )
    }

    func testAIHotAttributionRejectsLookalikeHost() {
        let data = Data(
            #"{"name":"AI HOT","url":"https://aihot.virxact.com.example.com/items/1"}"#.utf8
        )

        XCTAssertThrowsError(
            try AIHotJSON.decoder().decode(AIHotAttribution.self, from: data)
        )
    }

    func testAIHotAttributionRejectsNonstandardPort() {
        let data = Data(
            #"{"name":"AI HOT","url":"https://aihot.virxact.com:444/items/1"}"#.utf8
        )

        XCTAssertThrowsError(
            try AIHotJSON.decoder().decode(AIHotAttribution.self, from: data)
        )
    }

    func testAIHotItemsRequestUsesV1FiltersAndOpaqueCursor() throws {
        let query = AIHotItemsQuery(
            category: .paper,
            window: .day,
            searchText: "  RAG 检索  ",
            limit: 25
        )

        let request = try AIHotClient().makeItemsRequest(
            query: query,
            cursor: "opaque+/=cursor"
        )
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        let parameters = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        XCTAssertEqual(components.path, "/api/v1/items")
        XCTAssertEqual(parameters["mode"]!, "selected")
        XCTAssertEqual(parameters["window"]!, "24h")
        XCTAssertEqual(parameters["by"]!, "timeline")
        XCTAssertEqual(parameters["category"]!, "paper")
        XCTAssertEqual(parameters["q"]!, "RAG 检索")
        XCTAssertEqual(parameters["limit"]!, "25")
        XCTAssertEqual(parameters["cursor"]!, "opaque+/=cursor")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAIHotItemsRequestRejectsSingleCharacterSearch() {
        let query = AIHotItemsQuery(searchText: "AI".prefix(1).description)

        XCTAssertThrowsError(try AIHotClient().makeItemsRequest(query: query)) { error in
            guard case AIHotClientError.invalidSearchLength = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAIHotCacheReusesFreshResponseWithoutNetworkRequest() async throws {
        let cache = AIHotResponseCache()
        let request = URLRequest(url: URL(string: "https://example.com/feed?page=1")!)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("cached".utf8)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"feed-v1\""]
            )
        )

        guard case .network = await cache.plan(for: request, at: start) else {
            return XCTFail("The first request should use the network")
        }
        await cache.store(data, response: response, for: request, at: start)

        switch await cache.plan(for: request, at: start.addingTimeInterval(30)) {
        case let .cached(cachedData):
            XCTAssertEqual(cachedData, data)
        default:
            XCTFail("A fresh response should be served from memory")
        }
    }

    func testAIHotCacheAddsValidatorsAfterMinimumInterval() async throws {
        let cache = AIHotResponseCache()
        let request = URLRequest(url: URL(string: "https://example.com/feed?page=2")!)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("cached".utf8)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "ETag": "\"feed-v2\"",
                    "Last-Modified": "Sat, 25 Jul 2026 12:00:00 GMT",
                ]
            )
        )

        _ = await cache.plan(for: request, at: start)
        await cache.store(data, response: response, for: request, at: start)

        switch await cache.plan(for: request, at: start.addingTimeInterval(61)) {
        case let .network(conditionalRequest, cachedData):
            XCTAssertEqual(
                conditionalRequest.value(forHTTPHeaderField: "If-None-Match"),
                "\"feed-v2\""
            )
            XCTAssertEqual(
                conditionalRequest.value(forHTTPHeaderField: "If-Modified-Since"),
                "Sat, 25 Jul 2026 12:00:00 GMT"
            )
            XCTAssertEqual(cachedData, data)
        default:
            XCTFail("An expired response should be conditionally revalidated")
        }
    }

    func testAIHotCacheThrottlesRepeatedRequestWithoutCachedData() async {
        let cache = AIHotResponseCache()
        let request = URLRequest(url: URL(string: "https://example.com/feed?page=3")!)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        guard case .network = await cache.plan(for: request, at: start) else {
            return XCTFail("The first request should use the network")
        }

        switch await cache.plan(for: request, at: start.addingTimeInterval(10)) {
        case let .throttled(retryAfter):
            XCTAssertEqual(retryAfter, 50)
        default:
            XCTFail("A repeated uncached request should be throttled locally")
        }
    }

    func testAIHotCacheHonorsLongerServerRetryAfter() async {
        let cache = AIHotResponseCache()
        let request = URLRequest(url: URL(string: "https://example.com/feed?page=4")!)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = await cache.plan(for: request, at: start)
        await cache.deferRequest(for: request, retryAfter: 120, at: start)

        switch await cache.plan(for: request, at: start.addingTimeInterval(61)) {
        case let .throttled(retryAfter):
            XCTAssertEqual(retryAfter, 59)
        default:
            XCTFail("Retry-After should extend the minimum interval")
        }

        guard case .network = await cache.plan(
            for: request,
            at: start.addingTimeInterval(121)
        ) else {
            return XCTFail("The request should resume after Retry-After")
        }
    }

    func testAIHotCacheReusesDataAfterNotModifiedResponse() async throws {
        let cache = AIHotResponseCache()
        let request = URLRequest(url: URL(string: "https://example.com/feed?page=5")!)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("cached".utf8)
        let initialResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"feed-v5\""]
            )
        )
        let notModifiedResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 304,
                httpVersion: nil,
                headerFields: nil
            )
        )

        _ = await cache.plan(for: request, at: start)
        await cache.store(data, response: initialResponse, for: request, at: start)
        let revalidatedData = await cache.revalidatedData(
            for: request,
            response: notModifiedResponse,
            at: start.addingTimeInterval(61)
        )

        XCTAssertEqual(revalidatedData, data)
        switch await cache.plan(for: request, at: start.addingTimeInterval(90)) {
        case let .cached(cachedData):
            XCTAssertEqual(cachedData, data)
        default:
            XCTFail("A 304 response should refresh the in-memory response")
        }
    }

    func testAIHotCacheEvictsOldestResponseAtCapacity() async throws {
        let cache = AIHotResponseCache()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0...AIHotResponseCache.maximumEntryCount {
            let request = URLRequest(
                url: URL(string: "https://example.com/feed?page=\(index)")!
            )
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            let date = start.addingTimeInterval(TimeInterval(index))
            _ = await cache.plan(for: request, at: date)
            await cache.store(Data("\(index)".utf8), response: response, for: request, at: date)
        }

        let oldestRequest = URLRequest(
            url: URL(string: "https://example.com/feed?page=0")!
        )
        switch await cache.plan(for: oldestRequest, at: start.addingTimeInterval(300)) {
        case let .network(_, cachedData):
            XCTAssertNil(cachedData)
        default:
            XCTFail("The oldest cached response should be evicted")
        }
    }

    func testAIHotDailyResponseAllowsMissingCanonicalItemLink() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "report": {
                "date": "2026-07-25",
                "generatedAt": "2026-07-25T00:01:00Z",
                "windowStart": "2026-07-24T00:00:00Z",
                "windowEnd": "2026-07-25T00:00:00Z",
                "links": { "aihot": "https://aihot.virxact.com/daily/2026-07-25" },
                "attribution": {
                  "name": "AI HOT",
                  "url": "https://aihot.virxact.com/daily/2026-07-25"
                },
                "lead": null,
                "sections": [
                  {
                    "label": "模型发布/更新",
                    "items": [
                      {
                        "title": "模型更新",
                        "summary": "更新摘要",
                        "source": { "name": "Model Lab" },
                        "links": {
                          "aihot": null,
                          "original": "https://example.com/model"
                        }
                      }
                    ]
                  }
                ],
                "flashes": []
              }
            }
            """#.utf8
        )

        let response = try AIHotJSON.decoder().decode(AIHotDailyResponse.self, from: data)

        XCTAssertNil(response.report.sections[0].items[0].links.aihot)
        XCTAssertEqual(response.report.sections[0].items[0].source.name, "Model Lab")
    }

    func testAIHotViewModelPaginatesAndRemovesDuplicateItems() async {
        let firstItem = makeAIHotItem(id: "first", title: "第一条")
        let secondItem = makeAIHotItem(id: "second", title: "第二条")
        let service = AIHotServiceStub(
            itemResponses: [
                makeAIHotResponse(
                    items: [firstItem],
                    hasMore: true,
                    nextCursor: "next-page"
                ),
                makeAIHotResponse(
                    items: [firstItem, secondItem],
                    hasMore: false,
                    nextCursor: nil
                ),
            ]
        )
        let viewModel = AIHotViewModel(service: service)

        await viewModel.reloadItems()
        await viewModel.loadMoreItems()

        XCTAssertEqual(viewModel.items.map(\.id), ["first", "second"])
        XCTAssertEqual(service.requestedCursors.count, 2)
        XCTAssertNil(service.requestedCursors[0])
        XCTAssertEqual(service.requestedCursors[1], "next-page")
        XCTAssertFalse(viewModel.hasMoreItems)
    }

    func testAIHotViewModelValidatesSearchBeforeRequesting() async {
        let service = AIHotServiceStub(itemResponses: [])
        let viewModel = AIHotViewModel(service: service)
        viewModel.searchText = "A"

        await viewModel.submitSearch()

        XCTAssertEqual(viewModel.validationMessage, "搜索词需要包含 2 到 200 个字符。")
        XCTAssertTrue(service.requestedCursors.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TopicRecord.self,
            SearchRecord.self,
            configurations: configuration
        )
    }

    private func makeAIHotResponse(
        items: [AIHotItem],
        hasMore: Bool,
        nextCursor: String?
    ) -> AIHotItemsResponse {
        AIHotItemsResponse(
            schemaVersion: 1,
            query: AIHotResolvedQuery(
                mode: "selected",
                category: nil,
                window: "7d",
                q: nil,
                by: "timeline",
                ordering: "timelineDesc"
            ),
            items: items,
            page: AIHotPage(
                count: items.count,
                hasMore: hasMore,
                nextCursor: nextCursor
            )
        )
    }

    private func makeAIHotItem(id: String, title: String) -> AIHotItem {
        AIHotItem(
            id: id,
            title: title,
            originalTitle: nil,
            summary: "摘要",
            source: AIHotSource(name: "Test Source"),
            links: AIHotContentLinks(
                aihot: URL(string: "https://aihot.virxact.com/items/\(id)")!,
                original: URL(string: "https://example.com/\(id)")!
            ),
            publishedAt: nil,
            discoveredAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: "industry",
            score: 80,
            selected: true,
            attribution: nil
        )
    }

    private func credentialBearingURL(host: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.user = "placeholder-user"
        components.password = "placeholder-value"
        components.path = path
        return components.url!
    }
}

private final class AIHotServiceStub: AIHotServing {
    private var itemResponses: [AIHotItemsResponse]
    private(set) var requestedCursors: [String?] = []

    init(itemResponses: [AIHotItemsResponse]) {
        self.itemResponses = itemResponses
    }

    func fetchItems(
        query: AIHotItemsQuery,
        cursor: String?
    ) async throws -> AIHotItemsResponse {
        requestedCursors.append(cursor)
        guard !itemResponses.isEmpty else {
            throw AIHotServiceStubError.unconfigured
        }
        return itemResponses.removeFirst()
    }

    func fetchHotTopics() async throws -> AIHotTopicsResponse {
        throw AIHotServiceStubError.unconfigured
    }

    func fetchLatestDaily() async throws -> AIHotDailyResponse {
        throw AIHotServiceStubError.unconfigured
    }
}

private enum AIHotServiceStubError: Error {
    case unconfigured
}
