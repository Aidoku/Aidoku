//
//  WebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    @Binding var cookies: [String: String]

    init(_ url: URL, cookies: Binding<[String: String]> = .constant([:])) {
        self.url = url
        self._cookies = cookies
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        .init(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                let cookies = await webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
            }
        }
    }
}
