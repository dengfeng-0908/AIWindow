import SwiftUI

struct TopicAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TopicAnalysisViewModel

    init(context: TopicAnalysisContext) {
        _viewModel = StateObject(
            wrappedValue: TopicAnalysisViewModel(context: context)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("当前帖子") {
                    Text(viewModel.context.title)
                        .font(.headline)
                        .lineLimit(3)
                    LabeledContent("发送范围", value: viewModel.context.scopeDescription)
                }

                Section("你想了解什么") {
                    TextEditor(text: $viewModel.question)
                        .frame(minHeight: 100)
                        .disabled(viewModel.isAnalyzing)
                        .onChange(of: viewModel.question) { _, newValue in
                            if newValue.count > 2_000 {
                                viewModel.question = String(newValue.prefix(2_000))
                            }
                        }

                    Button(action: viewModel.submit) {
                        Label(
                            viewModel.result == nil ? "开始分析" : "重新分析",
                            systemImage: "sparkles"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing || viewModel.questionIsEmpty)
                }

                if viewModel.isAnalyzing {
                    Section {
                        ProgressView("正在等待模型返回…")
                    }
                }

                if let result = viewModel.result {
                    Section("分析结果") {
                        Text(verbatim: result)
                            .textSelection(.enabled)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("AI 分析")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear(perform: viewModel.cancel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: dismiss.callAsFunction)
                }
            }
            .confirmationDialog(
                "发送当前帖子文字？",
                isPresented: $viewModel.showsTransmissionConfirmation,
                titleVisibility: .visible
            ) {
                Button("发送并分析", action: viewModel.confirmTransmissionAndSubmit)
                Button("取消", role: .cancel) {}
            } message: {
                Text(
                    "本次会把上方范围内的帖子文字和你的问题发送到 "
                    + viewModel.pendingProviderHost
                    + "。不会发送 Cookie、密码或其他浏览记录。"
                )
            }
        }
    }
}

@MainActor
final class TopicAnalysisViewModel: ObservableObject {
    let context: TopicAnalysisContext

    @Published var question = TopicAnalysisContext.defaultQuestion
    @Published private(set) var result: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAnalyzing = false
    @Published var showsTransmissionConfirmation = false
    @Published private(set) var pendingProviderHost = "模型服务"

    private let keyStore: any ModelAPIKeyStoring
    private var analysisTask: Task<Void, Never>?

    init(
        context: TopicAnalysisContext,
        keyStore: any ModelAPIKeyStoring = KeychainModelAPIKeyStore()
    ) {
        self.context = context
        self.keyStore = keyStore
    }

    deinit {
        analysisTask?.cancel()
    }

    var questionIsEmpty: Bool {
        question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() {
        guard !isAnalyzing else { return }
        do {
            guard let configuration = ModelConfigurationStore.load() else {
                throw TopicAnalysisSetupError.missingConfiguration
            }
            guard try keyStore.read() != nil else {
                throw ModelAnalysisError.missingAPIKey
            }

            pendingProviderHost = configuration.providerHost
            if ModelAnalysisConsentStore.hasAcknowledged(host: configuration.providerHost) {
                startAnalysis(configuration: configuration)
            } else {
                showsTransmissionConfirmation = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmTransmissionAndSubmit() {
        guard let configuration = ModelConfigurationStore.load() else {
            errorMessage = TopicAnalysisSetupError.missingConfiguration.localizedDescription
            return
        }
        ModelAnalysisConsentStore.acknowledge(host: configuration.providerHost)
        startAnalysis(configuration: configuration)
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    private func startAnalysis(configuration: ModelAPIConfiguration) {
        analysisTask?.cancel()
        isAnalyzing = true
        errorMessage = nil
        result = nil
        let submittedQuestion = question

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let apiKey = try keyStore.read() else {
                    throw ModelAnalysisError.missingAPIKey
                }
                let client = ModelAnalysisClient(
                    configuration: configuration,
                    apiKey: apiKey
                )
                let response = try await client.analyze(
                    context: context,
                    question: submittedQuestion
                )
                guard !Task.isCancelled else { return }
                result = response
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}

enum TopicAnalysisSetupError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        "请先在设置中填写模型 API 地址和模型名称。"
    }
}
