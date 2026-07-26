import Foundation
import SwiftData

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
        let cleanTitle = normalizedTitle(title, fallbackURL: canonicalURL)

        if let existing = try topic(for: canonicalString, in: context) {
            existing.title = cleanTitle
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

    private static func normalizedTitle(_ title: String?, fallbackURL: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallbackURL.absoluteString }

        let suffixes = [" - LINUX DO", " - LINUX.DO", " | LINUX DO"]
        return suffixes.reduce(trimmed) { current, suffix in
            current.hasSuffix(suffix) ? String(current.dropLast(suffix.count)) : current
        }
    }
}
