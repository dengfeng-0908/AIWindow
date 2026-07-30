import Foundation
import SwiftData

@Model
final class TopicRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var canonicalURL: String
    var title: String
    var firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int
    var hasHistory: Bool
    var isFavorite: Bool
    var favoritedAt: Date?
    var note: String
    var tagsStorage: String

    init(
        id: UUID = UUID(),
        canonicalURL: String,
        title: String,
        firstVisitedAt: Date = .now,
        lastVisitedAt: Date = .now,
        visitCount: Int = 1,
        hasHistory: Bool = true,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil,
        note: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.title = title
        self.firstVisitedAt = firstVisitedAt
        self.lastVisitedAt = lastVisitedAt
        self.visitCount = visitCount
        self.hasHistory = hasHistory
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        self.note = note
        tagsStorage = Self.encodeTags(tags)
    }

    var url: URL? {
        guard let storedURL = URL(string: canonicalURL) else { return nil }
        return TopicURLNormalizer.canonicalTopicURL(from: storedURL)
    }

    var displayTitle: String {
        guard let url else { return title }
        return TopicTitleNormalizer.normalized(title, fallbackURL: url)
    }

    var tags: [String] {
        get {
            tagsStorage
                .split(separator: "\n")
                .map(String.init)
        }
        set {
            tagsStorage = Self.encodeTags(newValue)
        }
    }

    private static func encodeTags(_ tags: [String]) -> String {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.localizedLowercase).inserted }
            .joined(separator: "\n")
    }
}
