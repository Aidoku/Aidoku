//
//  CloudflareHandler.swift
//  Aidoku
//
//  Created by Skitty on 6/15/25.
//

import WebKit

// handles requests blocked by cloudflare, retrieving new cookies from a webview
// and showing a popup to complete a captcha if necessary
actor CloudflareHandler: NSObject {
    static let shared = CloudflareHandler()

    private var shouldTimeout = true

    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var proxy: Proxy?

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

    func handle(request: URLRequest) async {
        // wait until previous request finishes
        while finishContinuation != nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard await addWebView(for: request) else { return }

        _ = await webView.load(request)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.finishContinuation = continuation

            // timeout after 12s if bypass doesn't work
            Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if self.shouldTimeout {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil

        proxy = nil

        Task { @MainActor in
            webView.removeFromSuperview()
#if !os(macOS)
            popupController?.dismiss(animated: true)
            popupController = nil
#endif
        }

        continuation.resume()
    }

    func proxy(for request: URLRequest) async -> Proxy {
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
        let js = """
        (document.querySelector('input[name="cf-turnstile-response"]') !== null
            || document.body.textContent.includes('Verify you are human by completing')) ? 1 : 0
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            if let found = result as? Int, found == 1 {
                Task {
                    await self?.showPopup(for: request)
                }
            }
        }
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigated(webView: webView, for: request)
        }
    }

    // handle web view reload/redirect
    nonisolated func navigated(webView: WKWebView, for request: URLRequest) async {
        let webViewCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

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

        // check for old (expired) clearance cookie
        let oldCookie = HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "cf_clearance" }

        // check for clearance cookie
        let hasClearance = webViewCookies.contains(where: {
            $0.name == "cf_clearance" &&
            $0.value != oldCookie?.value ?? "" &&
            ($0.domain.contains(url.host ?? "") || (url.host?.contains($0.domain) ?? false))
        })
        guard hasClearance else { return }

        await webView.removeFromSuperview()
#if !os(macOS)
        await self.popupController?.dismiss(animated: true)
#endif

        // remove old cookie and save new cookies for future requests
        if let oldCookie {
            HTTPCookieStorage.shared.deleteCookie(oldCookie)
        }
        HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)

        await self.finish()
    }

    // handle user popover dismiss
    nonisolated func canceled(request: URLRequest) async {
        await finish()
    }
}
