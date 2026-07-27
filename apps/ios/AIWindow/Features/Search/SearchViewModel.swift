import Foundation
import SwiftData

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var engine: SearchEngine = .linuxDO
    @Published var errorMessage: String?

    func makeSearchURL(in context: ModelContext) -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }
        guard let url = engine.searchURL(for: trimmedQuery) else {
            errorMessage = "无法生成搜索地址。"
            return nil
        }

        do {
            let engineRawValue = engine.rawValue
            var descriptor = FetchDescriptor<SearchRecord>(
                predicate: #Predicate { record in
                    record.query == trimmedQuery
                        && record.engineRawValue == engineRawValue
                }
            )
            descriptor.fetchLimit = 1

            if let existing = try context.fetch(descriptor).first {
                existing.searchedAt = .now
            } else {
                context.insert(SearchRecord(query: trimmedQuery, engine: engine))
            }
            try context.save()
            query = ""
            return url
        } catch {
            errorMessage = "无法保存搜索记录：\(error.localizedDescription)"
            return nil
        }
    }

    func prepare(_ record: SearchRecord) {
        query = record.query
        engine = record.engine
    }
}
