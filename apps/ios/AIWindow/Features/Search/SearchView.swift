import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SearchRecord.searchedAt, order: .reverse)
    private var searchHistory: [SearchRecord]

    @StateObject private var viewModel = SearchViewModel()
    @State private var navigationPath: [URL] = []
    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)

                        TextField("搜索 LINUX DO", text: $viewModel.query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit(performSearch)

                        if !viewModel.query.isEmpty {
                            Button {
                                viewModel.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("清空搜索词")
                        }
                    }

                    Picker("搜索引擎", selection: $viewModel.engine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button(action: performSearch) {
                        Label("搜索公开帖子", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("LINUX DO 账号") {
                    NavigationLink(value: linuxDOHomeURL) {
                        Label("打开 LINUX DO（可登录）", systemImage: "person.crop.circle")
                    }

                    Text(
                        "登录由 LINUX DO 网页处理，状态仅保存在本 App 沙盒；"
                        + "App 不读取或导出密码、验证码与 Cookie。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section {
                    if searchHistory.isEmpty {
                        ContentUnavailableView(
                            "暂无搜索记录",
                            systemImage: "text.magnifyingglass"
                        )
                    } else {
                        ForEach(searchHistory) { record in
                            Button {
                                viewModel.prepare(record)
                                performSearch()
                            } label: {
                                SearchHistoryRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("最近搜索")
                        Spacer()
                        if !searchHistory.isEmpty {
                            Button("清空") {
                                showsClearConfirmation = true
                            }
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationDestination(for: URL.self) { url in
                BrowserView(initialURL: url)
            }
            .confirmationDialog(
                "清空全部搜索记录？",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空搜索记录", role: .destructive, action: clearHistory)
                Button("取消", role: .cancel) {}
            }
            .alert("操作失败", isPresented: errorAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var linuxDOHomeURL: URL {
        URL(string: "https://linux.do/")!
    }

    private func performSearch() {
        if let url = viewModel.makeSearchURL(in: modelContext) {
            navigationPath.append(url)
        }
    }

    private func delete(_ record: SearchRecord) {
        modelContext.delete(record)
        do {
            try modelContext.save()
        } catch {
            viewModel.errorMessage = "无法删除搜索记录：\(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        do {
            try modelContext.delete(model: SearchRecord.self)
            try modelContext.save()
        } catch {
            viewModel.errorMessage = "无法清空搜索记录：\(error.localizedDescription)"
        }
    }
}

private struct SearchHistoryRow: View {
    let record: SearchRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.query)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(record.engine.displayName) · \(record.searchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
