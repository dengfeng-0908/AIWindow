import Foundation
import SwiftData
import SwiftUI

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext
    let initialURL: URL

    var body: some View {
        BrowserScreen(initialURL: initialURL, modelContext: modelContext)
    }
}

private struct BrowserScreen: View {
    @StateObject private var viewModel: BrowserViewModel

    init(initialURL: URL, modelContext: ModelContext) {
        _viewModel = StateObject(
            wrappedValue: BrowserViewModel(
                initialURL: initialURL,
                modelContext: modelContext
            )
        )
    }

    var body: some View {
        BrowserWebView(viewModel: viewModel)
            .overlay(alignment: .top) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(isPresented: persistentNavigationBinding) {
                if let url = viewModel.pendingPersistentURL {
                    BrowserView(initialURL: url)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: BrowserWebsiteDataController.dataDidClearNotification
                )
            ) { _ in
                viewModel.reloadAfterWebsiteDataClear()
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: viewModel.goBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!viewModel.canGoBack)
                    .accessibilityLabel("后退")

                    Button(action: viewModel.goForward) {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!viewModel.canGoForward)
                    .accessibilityLabel("前进")

                    Button(action: viewModel.reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")

                    Spacer()

                    Button(action: viewModel.toggleFavorite) {
                        Image(systemName: viewModel.isCurrentTopicFavorite ? "star.fill" : "star")
                    }
                    .disabled(TopicURLNormalizer.canonicalTopicURL(from: viewModel.currentURL ?? URL(fileURLWithPath: "/")) == nil)
                    .accessibilityLabel(viewModel.isCurrentTopicFavorite ? "取消收藏" : "收藏")

                    Menu {
                        Button(action: viewModel.copyLink) {
                            Label("复制链接", systemImage: "doc.on.doc")
                        }
                        .disabled(viewModel.currentURL == nil)

                        Button(action: viewModel.openInDefaultBrowser) {
                            Label("在默认浏览器中打开", systemImage: "arrow.up.right.square")
                        }
                        .disabled(viewModel.currentURL == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
            .alert("浏览器提示", isPresented: errorAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var persistentNavigationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingPersistentURL != nil },
            set: { if !$0 { viewModel.clearPendingPersistentNavigation() } }
        )
    }
}
