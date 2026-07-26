import Foundation
import SwiftData

@Model
final class SearchRecord {
    @Attribute(.unique) var id: UUID
    var query: String
    var engineRawValue: String
    var searchedAt: Date

    init(
        id: UUID = UUID(),
        query: String,
        engine: SearchEngine,
        searchedAt: Date = .now
    ) {
        self.id = id
        self.query = query
        engineRawValue = engine.rawValue
        self.searchedAt = searchedAt
    }

    var engine: SearchEngine {
        SearchEngine(rawValue: engineRawValue) ?? .bing
    }
}
