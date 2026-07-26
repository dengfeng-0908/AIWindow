import Combine
import Foundation

enum AIHotSection: String, CaseIterable, Identifiable {
    case selected
    case topics
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selected: return "精选"
        case .topics: return "热点"
        case .daily: return "日报"
        }
    }
}

@MainActor
final class AIHotViewModel: ObservableObject {
    @Published var section: AIHotSection = .selected
    @Published var category: AIHotCategory = .all
    @Published var window: AIHotWindow = .week
    @Published var searchText = ""

    @Published private(set) var submittedSearchText: String?
    @Published private(set) var validationMessage: String?

    @Published private(set) var items: [AIHotItem] = []
    @Published private(set) var isLoadingItems = false
    @Published private(set) var isLoadingMoreItems = false
    @Published private(set) var itemsErrorMessage: String?
    @Published private(set) var hasMoreItems = false

    @Published private(set) var topics: [AIHotTopic] = []
    @Published private(set) var isLoadingTopics = false
    @Published private(set) var topicsErrorMessage: String?

    @Published private(set) var dailyReport: AIHotDailyReport?
    @Published private(set) var isLoadingDaily = false
    @Published private(set) var dailyErrorMessage: String?

    private let service: AIHotServing
    private var nextItemsCursor: String?
    private var loadedItemsQuery: AIHotItemsQuery?
    private var hasLoadedTopics = false
    private var hasLoadedDaily = false
    private var itemsRequestID = UUID()

    init(service: AIHotServing = AIHotClient()) {
        self.service = service
    }

    var itemsQuery: AIHotItemsQuery {
        AIHotItemsQuery(
            category: category,
            window: window,
            searchText: submittedSearchText,
            limit: 30
        )
    }

    func loadItemsIfNeeded() async {
        guard loadedItemsQuery != itemsQuery else { return }
        await reloadItems()
    }

    func reloadItems() async {
        let query = itemsQuery
        let requestID = UUID()
        itemsRequestID = requestID

        if loadedItemsQuery != query {
            items = []
            nextItemsCursor = nil
            hasMoreItems = false
        }

        isLoadingItems = true
        isLoadingMoreItems = false
        itemsErrorMessage = nil

        do {
            let response = try await service.fetchItems(query: query, cursor: nil)
            guard requestID == itemsRequestID, query == itemsQuery else { return }

            items = response.items
            nextItemsCursor = response.page.nextCursor
            hasMoreItems = response.page.hasMore && response.page.nextCursor != nil
            loadedItemsQuery = query
            isLoadingItems = false
        } catch is CancellationError {
            if requestID == itemsRequestID {
                isLoadingItems = false
            }
        } catch {
            guard requestID == itemsRequestID, query == itemsQuery else { return }
            itemsErrorMessage = error.localizedDescription
            loadedItemsQuery = query
            isLoadingItems = false
        }
    }

    func loadMoreItems() async {
        let query = itemsQuery
        guard loadedItemsQuery == query,
              !isLoadingItems,
              !isLoadingMoreItems,
              hasMoreItems,
              let cursor = nextItemsCursor
        else {
            return
        }

        let requestID = itemsRequestID
        isLoadingMoreItems = true
        itemsErrorMessage = nil

        do {
            let response = try await service.fetchItems(query: query, cursor: cursor)
            guard requestID == itemsRequestID, query == itemsQuery else { return }

            var knownIDs = Set(items.map(\.id))
            items.append(contentsOf: response.items.filter { knownIDs.insert($0.id).inserted })
            nextItemsCursor = response.page.nextCursor
            hasMoreItems = response.page.hasMore && response.page.nextCursor != nil
            isLoadingMoreItems = false
        } catch is CancellationError {
            if requestID == itemsRequestID {
                isLoadingMoreItems = false
            }
        } catch {
            guard requestID == itemsRequestID, query == itemsQuery else { return }
            itemsErrorMessage = error.localizedDescription
            isLoadingMoreItems = false
        }
    }

    func submitSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if submittedSearchText != nil {
                submittedSearchText = nil
                await reloadItems()
            }
            return
        }

        guard (2...200).contains(trimmed.count) else {
            validationMessage = "搜索词需要包含 2 到 200 个字符。"
            return
        }

        submittedSearchText = trimmed
        await reloadItems()
    }

    func clearSearchIfNeeded() async {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              submittedSearchText != nil
        else {
            return
        }

        submittedSearchText = nil
        await reloadItems()
    }

    func clearValidationMessage() {
        validationMessage = nil
    }

    func loadTopicsIfNeeded() async {
        guard !hasLoadedTopics else { return }
        await reloadTopics()
    }

    func reloadTopics() async {
        isLoadingTopics = true
        topicsErrorMessage = nil

        do {
            let response = try await service.fetchHotTopics()
            topics = response.items
            hasLoadedTopics = true
            isLoadingTopics = false
        } catch is CancellationError {
            isLoadingTopics = false
        } catch {
            topicsErrorMessage = error.localizedDescription
            hasLoadedTopics = true
            isLoadingTopics = false
        }
    }

    func loadDailyIfNeeded() async {
        guard !hasLoadedDaily else { return }
        await reloadDaily()
    }

    func reloadDaily() async {
        isLoadingDaily = true
        dailyErrorMessage = nil

        do {
            dailyReport = try await service.fetchLatestDaily().report
            hasLoadedDaily = true
            isLoadingDaily = false
        } catch is CancellationError {
            isLoadingDaily = false
        } catch {
            dailyErrorMessage = error.localizedDescription
            hasLoadedDaily = true
            isLoadingDaily = false
        }
    }
}
