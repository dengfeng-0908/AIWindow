import Foundation
import SwiftData

enum TopicTitleNormalizer {
    static func normalized(_ title: String?, fallbackURL: URL) -> String {
        var candidate = title?
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ") ?? ""
        candidate = candidate.replacingOccurrences(
            of: #"^\(\d+\)\s*"#,
            with: "",
            options: .regularExpression
        )

        let suffixes = [" - LINUX DO", " - LINUX.DO", " | LINUX DO"]
        for suffix in suffixes where candidate.hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isUsable(candidate) else {
            return fallbackTitle(for: fallbackURL)
        }
        return candidate
    }

    static func fallbackTitle(for url: URL) -> String {
        let topicID = url.pathComponents.last(where: { component in
            !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
        })
        return topicID.map { "LINUX DO 帖子 #\($0)" } ?? "LINUX DO 帖子"
    }

    static func isFallback(_ title: String, for url: URL) -> Bool {
        title == fallbackTitle(for: url) || title == url.absoluteString
    }

    private static func isUsable(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }
        let lowercased = title.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return false
        }
        if title.hasSuffix("的搜索结果") || lowercased.hasSuffix("search results") {
            return false
        }
        return !["linux do", "linux.do", "浏览", "just a moment…", "just a moment..."]
            .contains(lowercased)
    }
}

@MainActor
enum TopicRepository {
    static func topic(for canonicalURL: String, in context: ModelContext) throws -> TopicRecord? {
        var descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { topic in
                topic.canonicalURL == canonicalURL
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    static func recordVisit(
        url: URL,
        title: String?,
        in context: ModelContext,
        at date: Date = .now
    ) throws -> TopicRecord? {
        guard let canonicalURL = TopicURLNormalizer.canonicalTopicURL(from: url) else {
            return nil
        }

        let canonicalString = canonicalURL.absoluteString
        let cleanTitle = TopicTitleNormalizer.normalized(title, fallbackURL: canonicalURL)

        if let existing = try topic(for: canonicalString, in: context) {
            let storedTitle = TopicTitleNormalizer.normalized(
                existing.title,
                fallbackURL: canonicalURL
            )
            if !TopicTitleNormalizer.isFallback(cleanTitle, for: canonicalURL)
                || TopicTitleNormalizer.isFallback(storedTitle, for: canonicalURL) {
                existing.title = cleanTitle
            }
            existing.lastVisitedAt = date
            existing.visitCount += 1
            existing.hasHistory = true
            try context.save()
            return existing
        }

        let record = TopicRecord(
            canonicalURL: canonicalString,
            title: cleanTitle,
            firstVisitedAt: date,
            lastVisitedAt: date
        )
        context.insert(record)
        try context.save()
        return record
    }

    static func updateTitle(
        _ title: String?,
        for topic: TopicRecord,
        in context: ModelContext
    ) throws {
        guard let canonicalURL = topic.url else { return }
        let cleanTitle = TopicTitleNormalizer.normalized(title, fallbackURL: canonicalURL)
        guard !TopicTitleNormalizer.isFallback(cleanTitle, for: canonicalURL),
              topic.title != cleanTitle else {
            return
        }
        topic.title = cleanTitle
        try context.save()
    }

    static func setFavorite(
        _ isFavorite: Bool,
        for topic: TopicRecord,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        topic.isFavorite = isFavorite
        topic.favoritedAt = isFavorite ? (topic.favoritedAt ?? date) : nil

        if !isFavorite && !topic.hasHistory {
            context.delete(topic)
        }
        try context.save()
    }

    static func removeFromHistory(_ topic: TopicRecord, in context: ModelContext) throws {
        if topic.isFavorite {
            topic.hasHistory = false
            topic.visitCount = 0
        } else {
            context.delete(topic)
        }
        try context.save()
    }

    static func clearHistory(in context: ModelContext) throws {
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        for topic in topics {
            if topic.isFavorite {
                topic.hasHistory = false
                topic.visitCount = 0
            } else {
                context.delete(topic)
            }
        }
        try context.save()
    }
}
