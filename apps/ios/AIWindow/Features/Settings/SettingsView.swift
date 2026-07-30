import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var topics: [TopicRecord]
    @Query private var searches: [SearchRecord]

    @State private var exportDocument: BackupFileDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showsClearConfirmation = false
    @State private var showsWebsiteDataClearConfirmation = false
    @State private var isClearingWebsiteData = false
    @State private var modelSelection = ModelConfigurationSelection.defaultSelection
    @State private var apiKeyInput = ""
    @State private var hasStoredAPIKey = false
    @State private var storedAPIKeyHost: String?
    @State private var hasStoredModelConfiguration = false
    @State private var statusTitle = ""
    @State private var statusMessage: String?

    private let apiKeyStore = KeychainModelAPIKeyStore()

    var body: some View {
        NavigationStack {
            List {
                Section("本地数据") {
                    LabeledContent("已存帖子数", value: "\(topics.count)")
                    LabeledContent("已存搜索数", value: "\(searches.count)")

                    Button(action: prepareExport) {
                        Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("导入 JSON 备份", systemImage: "square.and.arrow.down")
                    }
                }

                Section("AI 分析") {
                    Picker("模型服务", selection: modelProviderBinding) {
                        ForEach(ModelProviderPreset.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }

                    if modelSelection.provider == .custom {
                        TextField("完整 HTTPS API 地址", text: $modelSelection.customEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        TextField("模型名称", text: $modelSelection.customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else if let model = selectedModel {
                        Picker("模型", selection: modelPresetBinding) {
                            ForEach(modelSelection.provider.models) { option in
                                Text(option.title).tag(option.id)
                            }
                        }

                        Picker("推理强度", selection: $modelSelection.reasoningID) {
                            ForEach(model.reasoningOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }

                        if modelSelection.provider == .openAI {
                            Text("需要 OpenAI Platform API Key；ChatGPT 或 Codex 登录不能代替。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SecureField(
                        apiKeyPlaceholder,
                        text: $apiKeyInput
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button(action: saveModelSettings) {
                        Label("保存模型设置", systemImage: "checkmark.circle")
                    }

                    if hasStoredAPIKey || hasStoredModelConfiguration {
                        Button(role: .destructive, action: clearModelSettings) {
                            Label("清除模型设置", systemImage: "key.slash")
                        }
                    }
                }

                Section("LINUX DO 登录") {
                    Button(role: .destructive) {
                        showsWebsiteDataClearConfirmation = true
                    } label: {
                        Label("清除此 App 的登录状态", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isClearingWebsiteData)
                }

                Section {
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("清除全部本地数据", systemImage: "trash")
                    }
                    .disabled(topics.isEmpty && searches.isEmpty)
                }
            }
            .navigationTitle("设置")
            .onAppear(perform: loadModelSettings)
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    showStatus(title: "导出完成", message: "备份文件已存储。")
                case let .failure(error):
                    showStatus(title: "导出失败", message: error.localizedDescription)
                }
                exportDocument = nil
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: importBackup
            )
            .confirmationDialog(
                "清除全部收藏、历史、备注和搜索记录？此操作无法撤销。",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除全部本地数据", role: .destructive, action: clearAllData)
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog(
                "将退出本 App 中的 LINUX DO 登录，是否继续？",
                isPresented: $showsWebsiteDataClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "清除此 App 的登录状态",
                    role: .destructive,
                    action: clearWebsiteData
                )
                Button("取消", role: .cancel) {}
            }
            .alert(statusTitle, isPresented: statusAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "AIWindow-\(formatter.string(from: .now))"
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )
    }

    private var selectedModel: ModelPreset? {
        modelSelection.provider.model(id: modelSelection.modelID)
    }

    private var canReuseStoredAPIKey: Bool {
        guard hasStoredAPIKey,
              let storedAPIKeyHost,
              let configuration = try? ModelAPIConfiguration(selection: modelSelection)
        else {
            return false
        }
        return configuration.providerHost.lowercased() == storedAPIKeyHost
    }

    private var apiKeyPlaceholder: String {
        if canReuseStoredAPIKey {
            return "输入新 API Key 以替换"
        }
        return hasStoredAPIKey ? "输入该服务的 API Key" : "API Key"
    }

    private var modelProviderBinding: Binding<ModelProviderPreset> {
        Binding(
            get: { modelSelection.provider },
            set: { provider in
                var updated = modelSelection
                updated.provider = provider
                updated.modelID = provider.defaultModelID
                updated.reasoningID = provider
                    .model(id: provider.defaultModelID)?
                    .defaultReasoningID ?? "compatible"
                modelSelection = updated
            }
        )
    }

    private var modelPresetBinding: Binding<String> {
        Binding(
            get: { modelSelection.modelID },
            set: { modelID in
                guard let model = modelSelection.provider.model(id: modelID) else { return }
                modelSelection.modelID = model.id
                modelSelection.reasoningID = model.defaultReasoningID
            }
        )
    }

    private func prepareExport() {
        exportDocument = BackupFileDocument(
            payload: BackupService.makePayload(topics: topics, searches: searches)
        )
        isExporting = true
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile != false else {
                throw BackupError.invalidDocument
            }
            if let fileSize = values.fileSize,
               fileSize > BackupService.maximumDocumentBytes {
                throw BackupError.documentTooLarge
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let payload = try BackupService.decode(data)
            let summary = try BackupService.merge(payload, into: modelContext)
            showStatus(title: "导入完成", message: summary.message)
        } catch {
            showStatus(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func clearAllData() {
        do {
            try modelContext.delete(model: TopicRecord.self)
            try modelContext.delete(model: SearchRecord.self)
            try modelContext.save()
            showStatus(title: "已清除", message: "全部本地数据已清除。")
        } catch {
            showStatus(title: "清除失败", message: error.localizedDescription)
        }
    }

    private func clearWebsiteData() {
        isClearingWebsiteData = true
        BrowserWebsiteDataController.clearPersistentData {
            isClearingWebsiteData = false
            showStatus(
                title: "已清除",
                message: "已退出本 App 中的 LINUX DO 登录。"
            )
        }
    }

    private func loadModelSettings() {
        modelSelection = ModelConfigurationStore.savedSelection()
        let configuration = ModelConfigurationStore.load()
        hasStoredModelConfiguration = configuration != nil
        do {
            hasStoredAPIKey = try apiKeyStore.read() != nil
            storedAPIKeyHost = hasStoredAPIKey
                ? configuration?.providerHost.lowercased()
                : nil
        } catch {
            showStatus(title: "读取失败", message: error.localizedDescription)
        }
    }

    private func saveModelSettings() {
        do {
            let configuration = try ModelAPIConfiguration(selection: modelSelection)
            let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard canReuseStoredAPIKey || !trimmedKey.isEmpty else {
                throw ModelAPIKeyStoreError.emptyKey
            }
            if !trimmedKey.isEmpty {
                try apiKeyStore.save(trimmedKey)
                hasStoredAPIKey = true
                apiKeyInput = ""
            }
            _ = try ModelConfigurationStore.save(selection: modelSelection)
            hasStoredModelConfiguration = true
            storedAPIKeyHost = configuration.providerHost.lowercased()
            showStatus(title: "已保存", message: "模型设置已保存。")
        } catch {
            showStatus(title: "保存失败", message: error.localizedDescription)
        }
    }

    private func clearModelSettings() {
        do {
            try apiKeyStore.delete()
            ModelConfigurationStore.clear()
            ModelAnalysisConsentStore.clear()
            hasStoredAPIKey = false
            storedAPIKeyHost = nil
            hasStoredModelConfiguration = false
            modelSelection = .defaultSelection
            apiKeyInput = ""
            showStatus(title: "已清除", message: "模型设置已清除。")
        } catch {
            showStatus(title: "清除失败", message: error.localizedDescription)
        }
    }

    private func showStatus(title: String, message: String) {
        statusTitle = title
        statusMessage = message
    }
}
