//
//  OIDCLoginController.swift
//  Aidoku
//
//  Created by Skitty on 10/23/25.
//

import SwiftUI
import WebKit

struct OIDCLoginView: View {
    let loginURL: URL
    let cookieHandler: ([HTTPCookie]) -> Void

    @State private var webViewURL: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            OIDCLoginControllerView(loginURL: loginURL, webViewURL: $webViewURL) { cookies in
                cookieHandler(cookies)
                dismiss()
            }
            .ignoresSafeArea()
            .navigationTitle(webViewURL?.host ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct OIDCLoginControllerView: UIViewControllerRepresentable {
    let loginURL: URL
    @Binding var webViewURL: URL?
    let cookieHandler: ([HTTPCookie]) -> Void

    func makeUIViewController(context: Context) -> OIDCLoginController {
        .init(loginURL: loginURL, cookieHandler: cookieHandler)
    }

    func updateUIViewController(_ uiViewController: OIDCLoginController, context: Context) {
        webViewURL = uiViewController.webView.url
    }
}

private class OIDCLoginController: UIViewController, WKNavigationDelegate {
    let loginURL: URL
    let cookieHandler: ([HTTPCookie]) -> Void

    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: self.view.bounds, configuration: config)
        webView.navigationDelegate = self
        return webView
    }()

    init(loginURL: URL, cookieHandler: @escaping ([HTTPCookie]) -> Void) {
        self.loginURL = loginURL
        self.cookieHandler = cookieHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(webView)
        let request = URLRequest(url: loginURL)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url, url.scheme == "aidoku" {
            fetchCookies()
            return .cancel
        } else {
            return .allow
        }
    }

    func fetchCookies() {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            self.cookieHandler(cookies)
        }
    }
}
