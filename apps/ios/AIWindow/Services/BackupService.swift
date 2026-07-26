import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupPayload: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var topics: [TopicBackup]
    var searches: [SearchBackup]
}

struct TopicBackup: Codable {
    var canonicalURL: String
    var title: String
    var firstVisitedAt: Date
    var lastVisitedAt: Date
    var visitCount: Int
    var hasHistory: Bool
    var isFavorite: Bool
    var favoritedAt: Date?
    var note: String
    var tags: [String]
}

struct SearchBackup: Codable {
    var id: UUID
    var query: String
    var engine: SearchEngine
    var searchedAt: Date
}

struct ImportSummary {
    var addedTopics = 0
    var mergedTopics = 0
    var skippedTopics = 0
    var addedSearches = 0

    var message: String {
        "新增帖子 \(addedTopics) 条，合并 \(mergedTopics) 条，跳过 \(skippedTopics) 条；新增搜索记录 \(addedSearches) 条。"
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case documentTooLarge
    case tooManyRecords
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "不支持版本为 \(version) 的备份文件。"
        case .documentTooLarge:
            "备份文件过大，已停止导入。"
        case .tooManyRecords:
            "备份记录数量异常，已停止导入。"
        case .invalidDocument:
            "备份文件内容无效。"
        }
    }
}

enum BackupService {
    static let maximumDocumentBytes = 10 * 1024 * 1024
    static let maximumRecordsPerCollection = 20_000

    static func makePayload(
        topics: [TopicRecord],
        searches: [SearchRecord]
    ) -> BackupPayload {
        BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            exportedAt: .now,
            topics: topics.map {
                TopicBackup(
                    canonicalURL: $0.canonicalURL,
                    title: $0.title,
                    firstVisitedAt: $0.firstVisitedAt,
                    lastVisitedAt: $0.lastVisitedAt,
                    visitCount: $0.visitCount,
                    hasHistory: $0.hasHistory,
                    isFavorite: $0.isFavorite,
                    favoritedAt: $0.favoritedAt,
                    note: $0.note,
                    tags: $0.tags
                )
            },
            searches: searches.map {
                SearchBackup(
                    id: $0.id,
                    query: $0.query,
                    engine: $0.engine,
                    searchedAt: $0.searchedAt
                )
            }
        )
    }

    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        guard data.count <= maximumDocumentBytes else {
            throw BackupError.documentTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.schemaVersion == BackupPayload.currentSchemaVersion else {
            throw BackupError.unsupportedVersion(payload.schemaVersion)
        }
        guard payload.topics.count <= maximumRecordsPerCollection,
              payload.searches.count <= maximumRecordsPerCollection
        else {
            throw BackupError.tooManyRecords
        }
        guard payload.topics.allSatisfy(isValid),
              payload.searches.allSatisfy(isValid) else {
            throw BackupError.invalidDocument
        }
        return payload
    }

    @MainActor
    static func merge(_ payload: BackupPayload, into context: ModelContext) throws -> ImportSummary {
        var summary = ImportSummary()
        let existingTopics = try context.fetch(FetchDescriptor<TopicRecord>())
        var topicsByURL = Dictionary(
            uniqueKeysWithValues: existingTopics.map { ($0.canonicalURL, $0) }
        )

        for incoming in payload.topics {
            guard let rawURL = URL(string: incoming.canonicalURL),
                  let canonicalURL = TopicURLNormalizer.canonicalTopicURL(from: rawURL)
            else {
                summary.skippedTopics += 1
                continue
            }

            let canonicalString = canonicalURL.absoluteString
            if let local = topicsByURL[canonicalString] {
                merge(incoming, into: local, canonicalURL: canonicalString)
                summary.mergedTopics += 1
            } else {
                let title = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let topic = TopicRecord(
                    canonicalURL: canonicalString,
                    title: title.isEmpty ? canonicalString : title,
                    firstVisitedAt: incoming.firstVisitedAt,
                    lastVisitedAt: incoming.lastVisitedAt,
                    visitCount: max(0, incoming.visitCount),
                    hasHistory: incoming.hasHistory,
                    isFavorite: incoming.isFavorite,
                    favoritedAt: incoming.isFavorite ? incoming.favoritedAt : nil,
                    note: incoming.note,
                    tags: incoming.tags
                )
                context.insert(topic)
                topicsByURL[canonicalString] = topic
                summary.addedTopics += 1
            }
        }

        let existingSearches = try context.fetch(FetchDescriptor<SearchRecord>())
        var searchIDs = Set(existingSearches.map(\.id))
        for incoming in payload.searches where searchIDs.insert(incoming.id).inserted {
            let query = incoming.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }
            context.insert(
                SearchRecord(
                    id: incoming.id,
                    query: query,
                    engine: incoming.engine,
                    searchedAt: incoming.searchedAt
                )
            )
            summary.addedSearches += 1
        }

        try context.save()
        return summary
    }

    private static func merge(
        _ incoming: TopicBackup,
        into local: TopicRecord,
        canonicalURL: String
    ) {
        local.firstVisitedAt = min(local.firstVisitedAt, incoming.firstVisitedAt)
        local.lastVisitedAt = max(local.lastVisitedAt, incoming.lastVisitedAt)
        local.visitCount = max(local.visitCount, max(0, incoming.visitCount))
        local.hasHistory = local.hasHistory || incoming.hasHistory

        if incoming.isFavorite {
            local.isFavorite = true
            switch (local.favoritedAt, incoming.favoritedAt) {
            case let (localDate?, incomingDate?):
                local.favoritedAt = min(localDate, incomingDate)
            case (nil, let incomingDate?):
                local.favoritedAt = incomingDate
            case (nil, nil):
                local.favoritedAt = incoming.lastVisitedAt
            default:
                break
            }
        }

        if local.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            local.note = incoming.note
        }
        local.tags = local.tags + incoming.tags

        let incomingTitle = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.title == canonicalURL && !incomingTitle.isEmpty {
            local.title = incomingTitle
        }
    }

    private static func isValid(_ topic: TopicBackup) -> Bool {
        topic.canonicalURL.utf8.count <= 4_096
            && topic.title.utf8.count <= 100_000
            && topic.note.utf8.count <= 1_000_000
            && topic.tags.count <= 1_000
            && topic.tags.allSatisfy { $0.utf8.count <= 1_000 }
            && (-1_000_000_000...1_000_000_000).contains(topic.visitCount)
    }

    private static func isValid(_ search: SearchBackup) -> Bool {
        search.query.utf8.count <= 10_000
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var payload: BackupPayload

    init(payload: BackupPayload) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalidDocument
        }
        payload = try BackupService.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupService.encode(payload))
    }
}
