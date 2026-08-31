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
    let localStorageKeys: [String]
    let webView: WKWebView

    @Binding var cookies: [String: String]
    @Binding var localStorage: [String: String]
    @Binding var reloadToggle: Bool

    init(
        _ url: URL,
        key: String? = nil,
        localStorageKeys: [String] = [],
        cookies: Binding<[String: String]> = .constant([:]),
        localStorage: Binding<[String: String]> = .constant([:]),
        reloadToggle: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.localStorageKeys = localStorageKeys
        self._cookies = cookies
        self._localStorage = localStorage
        self._reloadToggle = reloadToggle
        let config = WKWebViewConfiguration()
        if let key {
            config.websiteDataStore = .forSource(key: key)
        }
        webView = WKWebView(frame: .zero, configuration: config)
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

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingCookies()
    }

    func makeCoordinator() -> Coordinator {
        .init(parent: self)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: WebView

        private let cookieStore: WKHTTPCookieStore
        private var isObservingCookies = false

        init(parent: WebView) {
            self.parent = parent
            self.cookieStore = parent.webView.configuration.websiteDataStore.httpCookieStore

            super.init()

            cookieStore.add(self)
            isObservingCookies = true
        }

        @MainActor
        func stopObservingCookies() {
            guard isObservingCookies else { return }
            cookieStore.remove(self)
            isObservingCookies = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task {
                let cookies = await webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
                if !parent.localStorageKeys.isEmpty {
                    let storage = await webView.getLocalStorage(keys: parent.localStorageKeys)
                    parent.localStorage = storage
                }
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task {
                let cookies = await parent.webView.getCookies(for: parent.url.host)
                parent.cookies = cookies
                if !parent.localStorageKeys.isEmpty {
                    let storage = await parent.webView.getLocalStorage(keys: parent.localStorageKeys)
                    parent.localStorage = storage
                }
            }
        }
    }
}
