//
//  WKWebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import WebKit

extension WKWebView {
    func getCookies(for domain: String? = nil) async -> [String: String]  {
        await withCheckedContinuation { continuation in
            configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var cookieDict = [String: String]()
                for cookie in cookies {
                    if let domain {
                        if cookie.domain.contains(domain) {
                            cookieDict[cookie.name] = cookie.value
                        }
                    } else {
                        cookieDict[cookie.name] = cookie.value
                    }
                }
                continuation.resume(returning: cookieDict)
            }
        }
    }

    func getLocalStorage(keys: [String]) async -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        let js = """
        (function() {
            var result = {};
            var keys = \(keys);
            for (var i = 0; i < keys.length; i++) {
                var key = keys[i];
                var value = localStorage.getItem(key);
                if (value) { result[key] = value; }
            }
            return result;
        })();
        """
        do {
            let result = try await evaluateJavaScript(js) as? [String: String]
            return result ?? [:]
        } catch {
            return [:]
        }
    }
}
