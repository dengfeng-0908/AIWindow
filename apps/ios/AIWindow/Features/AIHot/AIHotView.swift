import SwiftUI

struct AIHotView: View {
    @StateObject private var viewModel: AIHotViewModel
    @State private var navigationPath = NavigationPath()

    init(service: AIHotServing = AIHotClient()) {
        _viewModel = StateObject(
            wrappedValue: AIHotViewModel(service: service)
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Picker("资讯视图", selection: $viewModel.section) {
                    ForEach(AIHotSection.allCases) { section in
                        Text(section.displayName).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                if viewModel.section == .selected {
                    AIHotFilterBar(viewModel: viewModel)
                    Divider()
                }

                content
            }
            .navigationTitle("资讯")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AIHotItem.self) { item in
                AIHotItemDetailView(item: item)
            }
            .navigationDestination(for: AIHotTopic.self) { topic in
                AIHotTopicDetailView(topic: topic)
            }
            .navigationDestination(for: AIHotDailyItem.self) { item in
                AIHotDailyItemDetailView(item: item)
            }
            .navigationDestination(for: AIHotDailyFlash.self) { flash in
                AIHotDailyFlashDetailView(flash: flash)
            }
            .onChange(of: viewModel.category) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .onChange(of: viewModel.window) { _, _ in
                Task { await viewModel.reloadItems() }
            }
            .alert("无法搜索", isPresented: validationAlertBinding) {
                Button("好", role: .cancel) {
                    viewModel.clearValidationMessage()
                }
            } message: {
                Text(viewModel.validationMessage ?? "请检查搜索词。")
            }
        }
        .toolbar(navigationPath.isEmpty ? .visible : .hidden, for: .tabBar)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .selected:
            AIHotItemsView(viewModel: viewModel)
                .searchable(text: $viewModel.searchText, prompt: "搜索 AI 资讯")
                .onSubmit(of: .search) {
                    Task { await viewModel.submitSearch() }
                }
                .onChange(of: viewModel.searchText) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { await viewModel.clearSearchIfNeeded() }
                    }
                }
        case .topics:
            AIHotTopicsView(viewModel: viewModel)
        case .daily:
            AIHotDailyView(viewModel: viewModel)
        }
    }

    private var validationAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.validationMessage != nil },
            set: { if !$0 { viewModel.clearValidationMessage() } }
        )
    }
}

private struct AIHotFilterBar: View {
    @ObservedObject var viewModel: AIHotViewModel

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("时间范围", selection: $viewModel.window) {
                    ForEach(AIHotWindow.allCases) { window in
                        Text(window.displayName).tag(window)
                    }
                }
            } label: {
                Label(viewModel.window.displayName, systemImage: "calendar")
            }

            Menu {
                Picker("分类", selection: $viewModel.category) {
                    ForEach(AIHotCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            } label: {
                Label(viewModel.category.displayName, systemImage: viewModel.category.systemImage)
            }

            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background)
    }
}

private struct AIHotItemsView: View {
    @ObservedObject var viewModel: AIHotViewModel

    var body: some View {
        Group {
            if viewModel.items.isEmpty && viewModel.isLoadingItems {
                ProgressView("正在加载精选资讯…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty,
                      let errorMessage = viewModel.itemsErrorMessage {
                AIHotUnavailableView(
                    title: "无法加载资讯",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                ) {
                    await viewModel.reloadItems()
                }
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    viewModel.submittedSearchText == nil ? "暂无精选资讯" : "没有匹配的资讯",
                    systemImage: viewModel.submittedSearchText == nil
                        ? "newspaper"
                        : "magnifyingglass",
                    description: Text(emptyDescription)
                )
            } else {
                List {
                    if let errorMessage = viewModel.itemsErrorMessage {
                        AIHotInlineError(message: errorMessage) {
                            await viewModel.reloadItems()
                        }
                    }

                    ForEach(viewModel.items) { item in
                        NavigationLink(value: item) {
                            AIHotItemRow(item: item)
                        }
                    }

                    if viewModel.hasMoreItems {
                        Section {
                            Button {
                                Task { await viewModel.loadMoreItems() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if viewModel.isLoadingMoreItems {
                                        ProgressView()
                                    } else {
                                        Label("加载更多", systemImage: "arrow.down.circle")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(viewModel.isLoadingMoreItems)
                        }
                    }

                    AIHotAttributionSection()
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadItemsIfNeeded()
        }
        .refreshable {
            await viewModel.reloadItems()
        }
    }

    private var emptyDescription: String {
        if viewModel.submittedSearchText != nil {
            return "可以更换关键词、分类或时间范围。"
        }
        return "下拉刷新，或更换分类和时间范围。"
    }
}

private struct AIHotItemRow: View {
    let item: AIHotItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if let summary = item.cleanSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                Label(item.categoryName, systemImage: "tag")
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(item.source.name)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(item.displayDate.formatted(.relative(presentation: .named)))
                    .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct AIHotTopicsView: View {
    @ObservedObject var viewModel: AIHotViewModel

    var body: some View {
        Group {
            if viewModel.topics.isEmpty && viewModel.isLoadingTopics {
                ProgressView("正在加载热点…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.topics.isEmpty,
                      let errorMessage = viewModel.topicsErrorMessage {
                AIHotUnavailableView(
                    title: "无法加载热点",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                ) {
                    await viewModel.reloadTopics()
                }
            } else if viewModel.topics.isEmpty {
                ContentUnavailableView(
                    "暂无热点",
                    systemImage: "flame",
                    description: Text("AI HOT 暂未形成多来源热点。")
                )
            } else {
                List {
                    if let errorMessage = viewModel.topicsErrorMessage {
                        AIHotInlineError(message: errorMessage) {
                            await viewModel.reloadTopics()
                        }
                    }

                    Section("当前多来源热点") {
                        ForEach(viewModel.topics) { topic in
                            NavigationLink(value: topic) {
                                AIHotTopicRow(topic: topic)
                            }
                        }
                    }

                    AIHotAttributionSection()
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadTopicsIfNeeded()
        }
        .refreshable {
            await viewModel.reloadTopics()
        }
    }
}

private struct AIHotTopicRow: View {
    let topic: AIHotTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(topic.title)
                .font(.headline)
                .lineLimit(3)

            Text(topic.sourceNames.prefix(3).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(topic.sourceCount) 个来源", systemImage: "newspaper")
                if topic.signalCount > 0 {
                    Label("\(topic.signalCount) 条信号", systemImage: "waveform")
                }
                Spacer(minLength: 4)
                Text(topic.latestAt.formatted(.relative(presentation: .named)))
                    .fixedSize()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct AIHotDailyView: View {
    @ObservedObject var viewModel: AIHotViewModel

    var body: some View {
        Group {
            if viewModel.dailyReport == nil && viewModel.isLoadingDaily {
                ProgressView("正在加载日报…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.dailyReport == nil,
                      let errorMessage = viewModel.dailyErrorMessage {
                AIHotUnavailableView(
                    title: "无法加载日报",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark"
                ) {
                    await viewModel.reloadDaily()
                }
            } else if let report = viewModel.dailyReport {
                List {
                    if let errorMessage = viewModel.dailyErrorMessage {
                        AIHotInlineError(message: errorMessage) {
                            await viewModel.reloadDaily()
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(report.date, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let lead = report.lead {
                                Text(lead.title)
                                    .font(.headline)
                                Text(lead.leadParagraph)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    } header: {
                        Text("最新日报")
                    }

                    ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                        if !section.items.isEmpty {
                            Section(section.label) {
                                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                    NavigationLink(value: item) {
                                        AIHotDailyItemRow(item: item)
                                    }
                                }
                            }
                        }
                    }

                    if !report.flashes.isEmpty {
                        Section("快讯") {
                            ForEach(Array(report.flashes.enumerated()), id: \.offset) { _, flash in
                                NavigationLink(value: flash) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(flash.title)
                                            .font(.headline)
                                            .lineLimit(3)
                                        Text("\(flash.source.name) · \(flash.publishedAt.formatted(.relative(presentation: .named)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    Section {
                        Link(destination: report.links.aihot) {
                            Label("在 AI HOT 查看本期日报", systemImage: "safari")
                        }
                    } footer: {
                        AIHotAttributionLabel(
                            attribution: report.attribution,
                            fallbackURL: report.links.aihot
                        )
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("暂无日报", systemImage: "doc.text")
            }
        }
        .task {
            await viewModel.loadDailyIfNeeded()
        }
        .refreshable {
            await viewModel.reloadDaily()
        }
    }
}

private struct AIHotDailyItemRow: View {
    let item: AIHotDailyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
                .lineLimit(3)
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(item.source.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct AIHotUnavailableView: View {
    let title: String
    let message: String
    let systemImage: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct AIHotInlineError: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                Spacer(minLength: 4)
                Button("重试") {
                    Task { await retry() }
                }
            }
        }
    }
}

private struct AIHotAttributionSection: View {
    private let url = URL(string: "https://aihot.virxact.com")!

    var body: some View {
        Section {
            Link(destination: url) {
                Label("资讯由 AI HOT 提供", systemImage: "checkmark.seal")
            }
        }
    }
}

struct AIHotAttributionLabel: View {
    let attribution: AIHotAttribution?
    let fallbackURL: URL

    var body: some View {
        Link(destination: attribution?.url ?? fallbackURL) {
            Text("内容由 \(attribution?.name ?? "AI HOT") 提供")
        }
    }
}
