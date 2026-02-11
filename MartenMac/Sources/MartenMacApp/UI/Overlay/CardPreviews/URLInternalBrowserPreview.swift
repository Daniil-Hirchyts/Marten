import Foundation
import SwiftUI
import WebKit

struct URLInternalBrowserPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        load(url, in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.lastRequestedURLString != url.absoluteString else {
            return
        }
        load(url, in: nsView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastRequestedURLString = url.absoluteString
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var lastRequestedURLString: String?

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                let url = navigationAction.request.url
            else {
                return nil
            }

            webView.load(URLRequest(url: url))
            return nil
        }
    }
}
