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
    var sourceId: String?

    @Binding var cookies: [String: String]
    @Binding var reloadToggle: Bool

    let webView = WKWebView()

    init(
        _ url: URL,
        sourceId: String? = nil,
        cookies: Binding<[String: String]> = .constant([:]),
        reloadToggle: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.sourceId = sourceId
        self._cookies = cookies
        self._reloadToggle = reloadToggle
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: url))
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
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
        weak var webView: WKWebView?

        init(parent: WebView) {
            self.parent = parent
            super.init()
            WKWebsiteDataStore.default().httpCookieStore.add(self)
        }

        deinit {
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                if let sourceId = parent.sourceId {
                    let localStorage = await webView.getLocalStorage()
                    for (key, value) in localStorage {
                        UserDefaults.standard.set(value, forKey: "\(sourceId).\(key)")
                    }
                }

                let cookies = await webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                if let sourceId = parent.sourceId, let webView = self.webView {
                    let localStorage = await webView.getLocalStorage()
                    for (key, value) in localStorage {
                        UserDefaults.standard.set(value, forKey: "\(sourceId).\(key)")
                    }
                }

                if let webView = self.webView {
                    let cookies = await webView.getCookies(for: parent.url.host)
                    parent.cookies = cookies
                }
            }
        }
    }
}
