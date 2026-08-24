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

    private struct ChallengeKey: Hashable {
        let host: String

        init?(url: URL?) {
            guard let host = url?.host?.lowercased() else { return nil }
            self.host = host
        }
    }
    private struct ChallengeTask {
        let id: UUID
        let task: Task<Void, Error>
    }
    private var challenges: [ChallengeKey: ChallengeTask] = [:]

    private var shouldTimeout = true
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var proxy: Proxy?
    private var isChallengeActive = false
    private var challengeWaiters: [CheckedContinuation<Void, Never>] = []

    @MainActor
    private lazy var webView = WKWebView(frame: .zero)

    @MainActor
    private var popupController: WebViewViewController?

    @MainActor
    private var popupShown: Bool {
        popupController?.presentingViewController != nil
    }

    @MainActor
    private var parent: UIViewController? {
        (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController
    }

    @MainActor
    private var parentView: UIView? {
        parent?.view
    }

    enum HandleError: Error {
        case invalidRequest
        case missingParentView
        case timedOut
        case canceled
        case solveFailed
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
        // handle challenges one at a time, waiting for a solution for the request url host
        try await awaitChallenge(for: request)

        // retry request
        let newRequest = if let url = request.url {
            await AidokuRunner.Source.modify(url: url, request: request)
        } else {
            request
        }
        let (data, response) = try await URLSession.shared.data(for: newRequest)
        if
            let response = response as? HTTPURLResponse,
            shouldHandle(response: response, data: data)
        {
            throw HandleError.solveFailed
        }
        return (data, response)
    }
}

extension CloudflareHandler {
    private func completeChallenge(for request: URLRequest) async throws {
        shouldTimeout = true

        guard await addWebView(for: request) else { throw HandleError.missingParentView }

        _ = await webView.load(request)

        try await withCheckedThrowingContinuation { continuation in
            self.finishContinuation = continuation

            // timeout after 12s if bypass doesn't work
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }

                if self.shouldTimeout, finishContinuation != nil {
                    self.finishChallenge(with: .failure(HandleError.timedOut))
                }
            }
        }
    }

    private func finishChallenge(with result: Result<Void, Error> = .success(())) {
        guard let continuation = finishContinuation else { return }

        Task { @MainActor in
            webView.removeFromSuperview()
            popupController?.dismiss(animated: true)
            popupController = nil
        }

        timeoutTask?.cancel()
        finishContinuation = nil
        timeoutTask = nil
        proxy = nil

        continuation.resume(with: result)
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

        // match web view rendering mode with user agent
        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        let config = WKWebViewConfiguration()
        if let userAgent, userAgent.contains("iPhone") || userAgent.contains("iPad") {
            config.defaultWebpagePreferences.preferredContentMode = .mobile
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = await proxy(for: request)
        webView.customUserAgent = userAgent
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

    private func awaitChallenge(for request: URLRequest) async throws {
        guard let key = ChallengeKey(url: request.url) else {
            throw HandleError.invalidRequest
        }

        if let challenge = challenges[key] {
            return try await challenge.task.value
        }

        let id = UUID()

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }

            await self.acquire()

            do {
                try Task.checkCancellation()
                try await self.completeChallenge(for: request)
                await self.release()
            } catch {
                await self.release()
                throw error
            }
        }

        challenges[key] = .init(id: id, task: task)

        do {
            try await task.value
        } catch {
            if challenges[key]?.id == id {
                challenges[key] = nil
            }
            throw error
        }

        if challenges[key]?.id == id {
            challenges[key] = nil
        }
    }

    private func acquire() async {
        guard !isChallengeActive else {
            await withCheckedContinuation { continuation in
                challengeWaiters.append(continuation)
            }
            return
        }
        isChallengeActive = true
    }

    private func release() {
        if !challengeWaiters.isEmpty {
            challengeWaiters.removeFirst().resume()
        } else {
            isChallengeActive = false
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
        guard let url = request.url, let host = url.host?.lowercased() else { return }

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

        var webViewCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

        // check for old (expired) clearance cookie
        let oldCookie = HTTPCookieStorage.shared.allCookies(for: url)?.first { $0.name == "cf_clearance" }

        // check for clearance cookie
        let hasClearance = webViewCookies.contains { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cookie.name == "cf_clearance"
                && cookie.value != oldCookie?.value
                && (host == domain || host.hasSuffix("." + domain))
        }
        guard hasClearance else { return }

        // remove old cookie and save new cookies for future requests
        if let oldCookie {
            HTTPCookieStorage.shared.deleteCookie(oldCookie)
            if let idx = webViewCookies.firstIndex(of: oldCookie) {
                webViewCookies.remove(at: idx)
            }
        }
        HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)

        let isCaptcha = await isCaptchaPage()
        guard !isCaptcha else { return }

        await webView.removeFromSuperview()
        await self.popupController?.dismiss(animated: true)

        await self.finishChallenge()
    }

    // handle user popover dismiss
    nonisolated func canceled(request: URLRequest) async {
        await self.finishChallenge(with: .failure(HandleError.canceled))
    }
}

extension CloudflareHandler {
    private func disableTimeout() {
        shouldTimeout = false
    }

    // show captcha sheet view to user
    @MainActor
    private func showPopup(for request: URLRequest) async {
        guard !popupShown else { return }

        // don't timeout while popup is shown
        await disableTimeout()

        guard let parent else {
            await self.finishChallenge(with: .failure(HandleError.missingParentView))
            return
        }

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

        parent.present(popup, animated: true)
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

extension HTTPCookieStorage {
    func allCookies(for url: URL) -> [HTTPCookie]? {
        guard let host = url.host else { return nil }
        return cookies?.filter { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
