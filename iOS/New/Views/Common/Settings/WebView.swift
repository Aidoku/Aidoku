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
    @Binding var reloadToggle: Bool

    private let webView = WKWebView()

    init(
        _ url: URL,
        cookies: Binding<[String: String]> = .constant([:]),
        reloadToggle: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self._cookies = cookies
        self._reloadToggle = reloadToggle
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if reloadToggle {
            reloadToggle = false
            uiView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        .init(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: WebView

        init(parent: WebView) {
            self.parent = parent
            super.init()
            WKWebsiteDataStore.default().httpCookieStore.add(self)
        }

        deinit {
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                let cookies = await webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task {
                let cookies = await parent.webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
            }
        }
    }
}
