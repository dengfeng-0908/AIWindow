import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TopicRecord.lastVisitedAt, order: .reverse)
    private var allTopics: [TopicRecord]

    @State private var searchText = ""
    @State private var showsClearConfirmation = false
    @State private var errorMessage: String?

    private var history: [TopicRecord] {
        allTopics.filter { topic in
            guard topic.hasHistory else { return false }
            let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return topic.displayTitle.localizedCaseInsensitiveContains(needle)
                || topic.canonicalURL.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无浏览记录" : "没有匹配的记录",
                        systemImage: searchText.isEmpty ? "clock" : "magnifyingglass"
                    )
                } else {
                    List {
                        ForEach(history) { topic in
                            if let url = topic.url {
                                NavigationLink {
                                    BrowserView(initialURL: url)
                                } label: {
                                    TopicRow(topic: topic, showsVisitCount: true)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        removeFromHistory(topic)
                                    } label: {
                                        Label("删除记录", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索标题或链接")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !history.isEmpty {
                        Button {
                            showsClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("清空浏览记录")
                    }
                }
            }
            .confirmationDialog(
                "清空全部浏览记录？收藏的帖子仍会保留。",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空浏览记录", role: .destructive, action: clearHistory)
                Button("取消", role: .cancel) {}
            }
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

    private func removeFromHistory(_ topic: TopicRecord) {
        do {
            try TopicRepository.removeFromHistory(topic, in: modelContext)
        } catch {
            errorMessage = "无法删除浏览记录：\(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        do {
            try TopicRepository.clearHistory(in: modelContext)
        } catch {
            errorMessage = "无法清空浏览记录：\(error.localizedDescription)"
        }
    }
}
