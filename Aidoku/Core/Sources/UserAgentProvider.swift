//
//  UserAgentProvider.swift
//  Aidoku
//
//  Created by Skitty on 3/24/25.
//

import WebKit

actor UserAgentProvider {
    static let shared = UserAgentProvider()

    private var userAgent: String?
    private var loadTask: Task<String?, Never>?

    private init() {}

    func getUserAgent() async -> String? {
        if let userAgent {
            return userAgent
        }

        if let loadTask {
            return await loadTask.value
        }

        let task = Task<String?, Never> { @MainActor in
            let webView = WKWebView()

            do {
                return try await webView.evaluateJavaScript(
                    "navigator.userAgent"
                ) as? String
            } catch {
                LogManager.logger.error(
                    "Error getting user agent: \(error)"
                )
                return nil
            }
        }
        loadTask = task

        let userAgent = await task.value

        self.userAgent = userAgent
        loadTask = nil

        return userAgent
    }
}
