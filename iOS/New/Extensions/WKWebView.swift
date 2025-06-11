//
//  WKWebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import WebKit

extension WKWebView {
    private var httpCookieStore: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    func getCookies(for domain: String? = nil) async -> [String: String]  {
        await withCheckedContinuation { continuation in
            httpCookieStore.getAllCookies { cookies in
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
}
