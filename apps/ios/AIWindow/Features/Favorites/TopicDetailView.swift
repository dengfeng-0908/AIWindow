import SwiftData
import SwiftUI
import UIKit

struct TopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var topic: TopicRecord

    @State private var tagsText: String
    @State private var note: String
    @State private var saveMessage: String?

    init(topic: TopicRecord) {
        self.topic = topic
        _tagsText = State(initialValue: topic.tags.joined(separator: "，"))
        _note = State(initialValue: topic.note)
    }

    var body: some View {
        Form {
            Section("帖子") {
                Text(topic.title)
                    .font(.headline)

                Text(topic.canonicalURL)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                LabeledContent("最后访问") {
                    Text(topic.lastVisitedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if topic.hasHistory {
                    LabeledContent("访问次数", value: "\(topic.visitCount)")
                }
            }

            Section("标签") {
                TextField("用逗号分隔", text: $tagsText, axis: .vertical)
                    .textInputAutocapitalization(.never)
            }

            Section("备注") {
                TextEditor(text: $note)
                    .frame(minHeight: 120)
            }

            Section {
                if let url = topic.url {
                    NavigationLink {
                        BrowserView(initialURL: url)
                    } label: {
                        Label("在 App 内打开", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("在默认浏览器中打开", systemImage: "arrow.up.right.square")
                    }

                    ShareLink(item: url) {
                        Label("分享链接", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("收藏详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("存储", action: save)
            }
        }
        .alert("提示", isPresented: saveAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "未知错误")
        }
    }

    private var saveAlertBinding: Binding<Bool> {
        Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )
    }

    private func save() {
        topic.tags = tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map(String.init)
        topic.note = note.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try modelContext.save()
            saveMessage = "已存储。"
        } catch {
            saveMessage = "无法存储：\(error.localizedDescription)"
        }
    }
}
