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
    @State private var statusTitle = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("本地数据") {
                    LabeledContent("帖子记录", value: "\(topics.count)")
                    LabeledContent("搜索记录", value: "\(searches.count)")

                    Button(action: prepareExport) {
                        Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("导入 JSON 备份", systemImage: "square.and.arrow.down")
                    }
                }

                Section("隐私") {
                    Label("帖子、收藏与备注只保存在本机", systemImage: "iphone")
                    Label("搜索引擎使用临时网页会话", systemImage: "hand.raised")
                    Label("LINUX DO 登录状态保存在 App 沙盒", systemImage: "person.badge.key")
                    Label("不包含广告、分析或账号 SDK", systemImage: "checkmark.shield")
                }

                Section("LINUX DO 登录") {
                    Text("不会读取或导出 Cookie、密码和验证码，也不会影响 Safari 的登录状态。")

                    Button(role: .destructive) {
                        showsWebsiteDataClearConfirmation = true
                    } label: {
                        Label("清除此 App 的登录状态", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isClearingWebsiteData)
                }

                Section("关于") {
                    Text(
                        "AI 视窗是独立开发的非官方客户端，"
                        + "与 AI HOT 和 LINUX DO 无隶属、合作或认可关系。"
                    )

                    Link(destination: URL(string: "https://aihot.virxact.com/terms")!) {
                        Label("AI HOT 公开接入条款", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://linux.do/tos")!) {
                        Label("LINUX DO 服务条款", systemImage: "doc.text")
                    }
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
                "清除此 App 保存的 LINUX DO Cookie、缓存和其他网页登录数据？这不会撤销其他设备的会话，也不会影响 Safari。",
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
                message: "此 App 的 LINUX DO 登录状态和持久网页数据已清除。"
            )
        }
    }

    private func showStatus(title: String, message: String) {
        statusTitle = title
        statusMessage = message
    }
}
