import MartenCore
import SwiftUI
import WebKit

struct URLViewerSheet: View {
    let item: ClipItem
    var onEdit: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var webViewState = WebViewState()
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let url {
                    WebView(url: url, state: webViewState)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Invalid URL",
                        systemImage: "link.badge.plus",
                        description: Text("This link cannot be opened.")
                    )
                }
            }
            .navigationTitle(pageTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }

                    if url != nil {
                        Button {
                            webViewState.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!webViewState.canGoBack)
                        
                        Button {
                            webViewState.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!webViewState.canGoForward)
                        
                        Button {
                            webViewState.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        
                        if let currentURL = webViewState.currentURL ?? url {
                            ShareLink(item: currentURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .task {
                loadURL()
            }
        }
    }
    
    private var pageTitle: String {
        if let title = webViewState.pageTitle, !title.isEmpty {
            return title
        }
        if let preview = item.linkPreview, let title = preview.title, !title.isEmpty {
            return title
        }
        return "Web Page"
    }
    
    private func loadURL() {
        guard let urlString = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            return
        }
        
        if let parsedURL = URL(string: urlString) {
            url = parsedURL
        } else if let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let parsedURL = URL(string: encodedString) {
            url = parsedURL
        }
    }
}

@MainActor
class WebViewState: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var pageTitle: String?
    @Published var currentURL: URL?
    
    var webView: WKWebView?
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
}

#if canImport(UIKit)
struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebViewState
    
    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        state.webView = webView
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let state: WebViewState
        
        init(state: WebViewState) {
            self.state = state
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
            updateState(from: webView)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            updateState(from: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
            updateState(from: webView)
        }
        
        private func updateState(from webView: WKWebView) {
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward
            state.pageTitle = webView.title
            state.currentURL = webView.url
        }
    }
}

#endif

#if canImport(AppKit)
struct WebView: NSViewRepresentable {
    let url: URL
    @ObservedObject var state: WebViewState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        state.webView = webView

        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let state: WebViewState

        init(state: WebViewState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
            updateState(from: webView)
        }

        private func updateState(from webView: WKWebView) {
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward
            state.pageTitle = webView.title
            state.currentURL = webView.url
        }
    }
}
#endif
