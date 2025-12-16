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

    @MainActor
    func getLocalStorage() async -> [String: String] {
        await withCheckedContinuation { continuation in
            evaluateJavaScript("""
            (function() {
                var obj = {};
                for (var i = 0; i < localStorage.length; i++) {
                    var key = localStorage.key(i);
                    obj[key] = localStorage.getItem(key);
                }
                return obj;
            })();
            """) { result, _ in
                continuation.resume(returning: (result as? [String: String]) ?? [:])
            }
        }
    }
}
