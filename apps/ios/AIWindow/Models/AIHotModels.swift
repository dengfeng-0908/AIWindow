import Foundation

enum AIHotWindow: String, CaseIterable, Identifiable, Hashable {
    case day = "24h"
    case week = "7d"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        }
    }
}

enum AIHotCategory: String, CaseIterable, Identifiable, Hashable {
    case all
    case models = "ai-models"
    case products = "ai-products"
    case industry
    case paper
    case tip

    var id: String { rawValue }

    var apiValue: String? {
        self == .all ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .all: "全部分类"
        case .models: "模型"
        case .products: "产品"
        case .industry: "行业"
        case .paper: "论文"
        case .tip: "技巧"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .models: "cpu"
        case .products: "shippingbox"
        case .industry: "building.2"
        case .paper: "doc.text"
        case .tip: "lightbulb"
        }
    }

    static func displayName(for apiValue: String?) -> String {
        guard let apiValue,
              let category = AIHotCategory(rawValue: apiValue)
        else {
            return apiValue == nil ? "未分类" : "其他"
        }
        return category.displayName
    }
}

struct AIHotItemsQuery: Hashable {
    var category: AIHotCategory = .all
    var window: AIHotWindow = .week
    var searchText: String?
    var limit = 30

    var normalizedSearchText: String? {
        let trimmed = searchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AIHotItemsResponse: Decodable, Hashable {
    let schemaVersion: Int
    let query: AIHotResolvedQuery
    let items: [AIHotItem]
    let page: AIHotPage
}

struct AIHotResolvedQuery: Decodable, Hashable {
    let mode: String
    let category: String?
    let window: String
    let q: String?
    let by: String
    let ordering: String
}

struct AIHotPage: Decodable, Hashable {
    let count: Int
    let hasMore: Bool
    let nextCursor: String?
}

struct AIHotItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let originalTitle: String?
    let summary: String?
    let source: AIHotSource
    let links: AIHotContentLinks
    let publishedAt: Date?
    let discoveredAt: Date
    let category: String?
    let score: Double?
    let selected: Bool
    let attribution: AIHotAttribution?

    var displayDate: Date {
        publishedAt ?? discoveredAt
    }

    var categoryName: String {
        AIHotCategory.displayName(for: category)
    }

    var cleanSummary: String? {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct AIHotSource: Decodable, Hashable {
    let name: String
}

struct AIHotContentLinks: Decodable, Hashable {
    let aihot: URL?
    let original: URL

    init(aihot: URL?, original: URL) {
        self.aihot = aihot
        self.original = original
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aihot = try container.decodeIfPresent(URL.self, forKey: .aihot)
        let original = try container.decode(URL.self, forKey: .original)

        if let aihot, !AIHotURLPolicy.isCanonicalURL(aihot) {
            throw DecodingError.dataCorruptedError(
                forKey: .aihot,
                in: container,
                debugDescription: "Invalid AI HOT canonical URL"
            )
        }
        guard AIHotURLPolicy.isWebURL(original) else {
            throw DecodingError.dataCorruptedError(
                forKey: .original,
                in: container,
                debugDescription: "Invalid original article URL"
            )
        }

        self.aihot = aihot
        self.original = original
    }

    private enum CodingKeys: String, CodingKey {
        case aihot
        case original
    }
}

struct AIHotPageLinks: Decodable, Hashable {
    let aihot: URL

    init(aihot: URL) {
        self.aihot = aihot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aihot = try container.decode(URL.self, forKey: .aihot)
        guard AIHotURLPolicy.isCanonicalURL(aihot) else {
            throw DecodingError.dataCorruptedError(
                forKey: .aihot,
                in: container,
                debugDescription: "Invalid AI HOT page URL"
            )
        }
        self.aihot = aihot
    }

    private enum CodingKeys: String, CodingKey {
        case aihot
    }
}

struct AIHotAttribution: Decodable, Hashable {
    let name: String
    let url: URL

    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let url = try container.decode(URL.self, forKey: .url)
        guard AIHotURLPolicy.isCanonicalURL(url) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Invalid AI HOT attribution URL"
            )
        }
        self.name = name
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case url
    }
}

struct AIHotTopicsResponse: Decodable, Hashable {
    let schemaVersion: Int
    let count: Int
    let items: [AIHotTopic]
}

struct AIHotTopic: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let source: AIHotSource
    let links: AIHotContentLinks
    let sourceCount: Int
    let signalCount: Int
    let sourceNames: [String]
    let latestAt: Date
}

struct AIHotDailyResponse: Decodable, Hashable {
    let schemaVersion: Int
    let report: AIHotDailyReport
}

struct AIHotDailyReport: Decodable, Hashable {
    let date: String
    let generatedAt: Date
    let windowStart: Date
    let windowEnd: Date
    let links: AIHotPageLinks
    let attribution: AIHotAttribution?
    let lead: AIHotDailyLead?
    let sections: [AIHotDailySection]
    let flashes: [AIHotDailyFlash]
}

struct AIHotDailyLead: Decodable, Hashable {
    let title: String
    let leadParagraph: String
}

struct AIHotDailySection: Decodable, Hashable {
    let label: String
    let items: [AIHotDailyItem]
}

struct AIHotDailyItem: Decodable, Hashable {
    let title: String
    let summary: String
    let source: AIHotSource
    let links: AIHotContentLinks
    let attribution: AIHotAttribution?
}

struct AIHotDailyFlash: Decodable, Hashable {
    let title: String
    let source: AIHotSource
    let links: AIHotContentLinks
    let publishedAt: Date
    let attribution: AIHotAttribution?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum AIHotURLPolicy {
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return false
        }
        return url.user == nil && url.password == nil
    }

    static func isCanonicalURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased().trimmingCharacters(
                  in: CharacterSet(charactersIn: ".")
              ) else {
            return false
        }
        return host == "aihot.virxact.com" && url.user == nil && url.password == nil
    }
}
