import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TopicRecord.lastVisitedAt, order: .reverse)
    private var allTopics: [TopicRecord]

    @State private var searchText = ""
    @State private var errorMessage: String?

    private var favorites: [TopicRecord] {
        allTopics.filter { topic in
            guard topic.isFavorite else { return false }
            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return topic.displayTitle.localizedCaseInsensitiveContains(needle)
                || topic.canonicalURL.localizedCaseInsensitiveContains(needle)
                || topic.note.localizedCaseInsensitiveContains(needle)
                || topic.tags.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无收藏" : "没有匹配的收藏",
                        systemImage: searchText.isEmpty ? "star" : "magnifyingglass"
                    )
                } else {
                    List {
                        ForEach(favorites) { topic in
                            NavigationLink {
                                TopicDetailView(topic: topic)
                            } label: {
                                TopicRow(topic: topic)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeFavorite(topic)
                                } label: {
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏")
            .searchable(text: $searchText, prompt: "标题、链接、标签或备注")
            .alert("操作失败", isPresented: errorAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func removeFavorite(_ topic: TopicRecord) {
        do {
            try TopicRepository.setFavorite(false, for: topic, in: modelContext)
        } catch {
            errorMessage = "无法取消收藏：\(error.localizedDescription)"
        }
    }
}
