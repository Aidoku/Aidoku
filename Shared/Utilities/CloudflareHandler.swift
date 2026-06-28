//
//  CloudflareHandler.swift
//  Aidoku
//
//  Created by Skitty on 6/15/25.
//

import AidokuRunner
import SwiftSoup
import WebKit

// handles requests blocked by cloudflare, retrieving new cookies from a webview
// and showing a popup to complete a captcha if necessary
actor CloudflareHandler: NSObject {
    static let shared = CloudflareHandler()

    private let blockedStatusCodes: Set<Int> = [403, 503]

    private var shouldTimeout = true
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var proxy: Proxy?
    private var lastMainFrameStatusCode: Int?

    @MainActor
    private lazy var webView = WKWebView(frame: .zero)

#if !os(macOS)
    @MainActor
    private var popupController: WebViewViewController?
#endif

    @MainActor
    private var popupShown: Bool {
#if !os(macOS)
        popupController?.presentingViewController != nil
#else
        false
#endif
    }

#if os(macOS)
    @MainActor
    private var parent: NSWindow? {
        NSApplication.shared.windows.first
    }

    @MainActor
    private var parentView: NSView? {
        parent?.contentView
    }
#else
    @MainActor
    private var parent: UIViewController? {
        (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController
    }

    @MainActor
    private var parentView: UIView? {
        parent?.view
    }
#endif

    enum HandleError: Error {
        case missingParentView
    }

    nonisolated func shouldHandle(response: HTTPURLResponse, data: Data) -> Bool {
        let server = response.value(forHTTPHeaderField: "Server")
        if !["cloudflare", "cloudflare-nginx"].contains(server) {
            return false
        }
        if !blockedStatusCodes.contains(response.statusCode) {
            return false
        }

        guard let html = String(data: data, encoding: .utf8) else { return false }
        do {
            let doc = try SwiftSoup.parse(html)
            if try doc.getElementById("challenge-error-title") != nil {
                return true
            }
            if try doc.getElementById("challenge-error-text") != nil {
                return true
            }
        } catch {}
        return false
    }

    func handle(request: URLRequest) async throws -> (Data, URLResponse) {
        // wait until previous request finishes
        while finishContinuation != nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        shouldTimeout = true

        guard await addWebView(for: request) else { throw HandleError.missingParentView }

        _ = await webView.load(request)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.finishContinuation = continuation

            // timeout after 12s if bypass doesn't work
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                if self.shouldTimeout, finishContinuation != nil {
                    self.finish()
                }
            }
        }

        let newRequest = if let url = request.url {
            await AidokuRunner.Source.modify(url: url, request: request)
        } else {
            request
        }
        return try await URLSession.shared.data(for: newRequest)
    }

    private func finish() {
        guard let continuation = finishContinuation else { return }

        Task { @MainActor in
            webView.removeFromSuperview()
#if !os(macOS)
            popupController?.dismiss(animated: true)
            popupController = nil
#endif
        }

        timeoutTask?.cancel()
        finishContinuation = nil
        timeoutTask = nil
        proxy = nil
        lastMainFrameStatusCode = nil

        continuation.resume()
    }

    private func proxy(for request: URLRequest) async -> Proxy {
        if let proxy {
            return proxy
        }
        let proxy = await Proxy(request: request, handler: self)
        self.proxy = proxy
        return proxy
    }

    // add hidden web view to a visible view controller
    @MainActor
    private func addWebView(for request: URLRequest) async -> Bool {
        guard let parentView else { return false }

        webView = WKWebView(frame: .zero)
        webView.navigationDelegate = await proxy(for: request)
        webView.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
        webView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: 0),
            webView.heightAnchor.constraint(equalToConstant: 0),
            webView.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor)
        ])

        return true
    }

    private func cancelTimeout() {
        shouldTimeout = false
    }

    // show captcha sheet view to user
    @MainActor
    private func showPopup(for request: URLRequest) async {
        guard !popupShown else { return }

        // cancel timeout
        await cancelTimeout()

#if os(macOS)
        // todo
        await finish()
#else
        popupController?.dismiss(animated: true)
        let popup = WebViewViewController(request: request, handler: await proxy(for: request))
        popupController = popup

        webView.navigationDelegate = popup
        webView.removeFromSuperview()
        popup.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalTo: popup.view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: popup.view.heightAnchor),
            webView.centerXAnchor.constraint(equalTo: popup.view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: popup.view.centerYAnchor)
        ])

        parent?.present(popup, animated: true)
#endif
    }

    // check if captcha or verify button is shown, and show the popup if it is
    @MainActor
    private func checkForCaptcha(for request: URLRequest) {
        guard !popupShown else { return }
        Task {
            let found = await isCaptchaPage()
            if found {
                await showPopup(for: request)
            }
        }
    }

    @MainActor
    private func isCaptchaPage() async -> Bool {
        let js = """
        (document.querySelector('input[name="cf-turnstile-response"]') !== null
            || document.getElementById('challenge-error-title') !== null
            || document.getElementById('challenge-error-text') !== null) ? 1 : 0
        """
        let result = try? await webView.evaluateJavaScript(js)
        guard let result = result as? Int else { return false }
        return result == 1
    }
}

extension CloudflareHandler {
    @MainActor
    final class Proxy: NSObject, PopupWebViewHandler, WKNavigationDelegate {
        let request: URLRequest

        weak var handler: CloudflareHandler?

        init(request: URLRequest, handler: CloudflareHandler) {
            self.request = request
            self.handler = handler
        }

        func navigated(webView: WKWebView, for request: URLRequest) {
            Task { [weak handler] in
                await handler?.navigated(webView: webView, for: request)
            }
        }

        func canceled(request: URLRequest) {
            Task { [weak handler] in
                await handler?.canceled(request: request)
            }
        }

        func handle(response: WKNavigationResponse) {
            guard
                response.isForMainFrame,
                let response = response.response as? HTTPURLResponse
            else { return }
            Task { [weak handler] in
                await handler?.setLastMainFrameStatusCode(response.statusCode)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigated(webView: webView, for: request)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            handle(response: navigationResponse)
            return .allow
        }
    }

    private func setLastMainFrameStatusCode(_ statusCode: Int) {
        lastMainFrameStatusCode = statusCode
    }

    // handle web view reload/redirect
    nonisolated func navigated(webView: WKWebView, for request: URLRequest) async {
        guard let url = request.url else { return }

#if !os(macOS)
        await MainActor.run {
            if self.popupController == nil {
                // delay captcha check by 3s (so it loads in)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.checkForCaptcha(for: request)
                }
                // try again in 5s if the first check didn't catch the captcha (dumb hack)
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    self?.checkForCaptcha(for: request)
                }
            }
        }
#endif

        var webViewCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

        // check for old (expired) clearance cookie
        let oldCookie = HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "cf_clearance" }

        // check for clearance cookie
        let hasClearance = webViewCookies.contains(where: {
            $0.name == "cf_clearance" &&
            $0.value != oldCookie?.value ?? "" &&
            ($0.domain.contains(url.host ?? "") || (url.host?.contains($0.domain) ?? false))
        })
        guard hasClearance else { return }

        // remove old cookie and save new cookies for future requests
        if let oldCookie {
            HTTPCookieStorage.shared.deleteCookie(oldCookie)
            if let idx = webViewCookies.firstIndex(of: oldCookie) {
                webViewCookies.remove(at: idx)
            }
        }
        HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)

        // ensure we're no longer blocked by cloudflare status or captcha
        if let statusCode = await self.lastMainFrameStatusCode, blockedStatusCodes.contains(statusCode) {
            return
        }
        let isCaptcha = await isCaptchaPage()
        guard !isCaptcha else { return }

        await webView.removeFromSuperview()
#if !os(macOS)
        await self.popupController?.dismiss(animated: true)
#endif

        await self.finish()
    }

    // handle user popover dismiss
    nonisolated func canceled(request: URLRequest) async {
        await finish()
    }
}
