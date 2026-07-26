import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeUIView(context: Context) -> WKWebView {
        viewModel.loadInitialURLIfNeeded()
        return viewModel.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
