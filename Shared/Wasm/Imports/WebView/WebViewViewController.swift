//
//  WebViewViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/23.
//

import UIKit
import WebKit

class WebViewViewController: BaseViewController, WKNavigationDelegate {

    var handler: WasmNetWebViewHandler?

    override func configure() {
        view.backgroundColor = .systemBackground
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        handler?.webView(webView, didFinish: navigation)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // if user dismissed the view without it succeeding
        if !(handler?.done ?? true) {
            handler?.webView.removeFromSuperview()
            handler?.netModule.semaphore.signal()
        }
        handler = nil
    }
}
