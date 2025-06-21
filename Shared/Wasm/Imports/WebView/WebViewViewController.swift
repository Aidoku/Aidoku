//
//  WebViewViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/23.
//

import UIKit
import WebKit

class WebViewViewController: BaseViewController, WKNavigationDelegate {
    let request: URLRequest
    var handler: PopupWebViewHandler?

    init(request: URLRequest, handler: PopupWebViewHandler? = nil) {
        self.request = request
        self.handler = handler
        super.init()
    }

    override func configure() {
        view.backgroundColor = .systemBackground
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        handler?.navigated(webView: webView, for: request)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        handler?.canceled(request: request)
        handler = nil
    }
}
