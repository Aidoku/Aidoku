//
//  WasmNet.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter
import SwiftSoup
import WebKit

enum HttpMethod: Int {
    case GET = 0
    case POST = 1
    case HEAD = 2
    case PUT = 3
    case DELETE = 4
}

class WasmResponseObject: KVCObject {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    var statusCode: Int?

    var bytesRead: Int = 0

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil, statusCode: Int? = nil) {
        self.data = data
        self.response = response
        self.error = error
        self.statusCode = statusCode ?? (response as? HTTPURLResponse)?.statusCode
    }

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "data": return data != nil ? [UInt8](data!) : []
        case "headers": return (response as? HTTPURLResponse)?.allHeaderFields
        case "status_code": return statusCode != nil ? statusCode : (response as? HTTPURLResponse)?.statusCode
        default: return nil
        }
    }
}

struct WasmRequestObject: KVCObject {
    let id: Int32
    var URL: String?
    var method: HttpMethod?
    var headers: [String: String?] = [:]
    var body: Data?

    var response: WasmResponseObject?

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "url": return URL
        case "method": return method?.rawValue
        case "headers": return headers
        case "body": return body
        case "response": return response
        default: return nil
        }
    }
}

// MARK: - Web View Handler
class WasmNetWebViewHandler: NSObject, WKNavigationDelegate {

    var netModule: WasmNet
    var request: URLRequest

    var webView: WKWebView?

    var done = false

    init(netModule: WasmNet, request: URLRequest) {
        self.netModule = netModule
        self.request = request
    }

    func load() {
        webView = WKWebView(frame: .zero)
        webView?.navigationDelegate = self
        webView?.customUserAgent = request.value(forHTTPHeaderField: "User-Agent")
        webView?.load(request)

        #if os(OSX)
        NSApplication.shared.windows.first?.contentView?.addSubview(webView!)
        #else
        UIApplication.shared.windows.first?.rootViewController?.view.addSubview(webView!)
        #endif

        // timeout after 12s if bypass doesn't work
        perform(#selector(timeout), with: nil, afterDelay: 12)
    }

    @objc func timeout() {
        if !done {
            done = true
            netModule.semaphore.signal()
            webView?.removeFromSuperview()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { webViewCookies in
            guard let url = self.request.url else { return }

            // check for old (expired) clearance cookie
            let oldCookie = HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == "cf_clearance" }

            // check for clearance cookie
            guard webViewCookies.contains(where: { $0.name == "cf_clearance" && $0.value != oldCookie?.value ?? "" }) else { return }

            webView.removeFromSuperview()
            self.done = true

            // save cookies for future requests
            HTTPCookieStorage.shared.setCookies(webViewCookies, for: url, mainDocumentURL: url)
            if let cookies = HTTPCookie.requestHeaderFields(with: webViewCookies)["Cookie"] {
                self.request.addValue(cookies, forHTTPHeaderField: "Cookie")
            }

            // re-send request
            URLSession.shared.dataTask(with: self.request) { data, response, error in
                self.netModule.storedResponse = WasmResponseObject(data: data, response: response, error: error)
                self.netModule.incrementRequest()
                self.netModule.semaphore.signal()
            }.resume()
        }
    }
}

// MARK: - Net Module
class WasmNet: WasmImports {

    var globalStore: WasmGlobalStore

    let semaphore = DispatchSemaphore(value: 0)

    var rateLimit: Int = -1 // how many requests to let through during the period
    var period: TimeInterval = 60 // seconds in the rate limit period
    var lastRequestTime: Date?
    var passedRequests: Int = 0

    var storedResponse: WasmResponseObject?

    // swiftlint:disable:next line_length
    static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.150 Safari/537.36 Edg/88.0.705.63"

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "net") {
        try? globalStore.vm.addImportHandler(named: "init", namespace: namespace, block: self.init_request)
        try? globalStore.vm.addImportHandler(named: "send", namespace: namespace, block: self.send)
        try? globalStore.vm.addImportHandler(named: "close", namespace: namespace, block: self.close)

        try? globalStore.vm.addImportHandler(named: "set_url", namespace: namespace, block: self.set_url)
        try? globalStore.vm.addImportHandler(named: "set_header", namespace: namespace, block: self.set_header)
        try? globalStore.vm.addImportHandler(named: "set_body", namespace: namespace, block: self.set_body)

        try? globalStore.vm.addImportHandler(named: "get_url", namespace: namespace, block: self.get_url)
        try? globalStore.vm.addImportHandler(named: "get_data_size", namespace: namespace, block: self.get_data_size)
        try? globalStore.vm.addImportHandler(named: "get_data", namespace: namespace, block: self.get_data)

        try? globalStore.vm.addImportHandler(named: "json", namespace: namespace, block: self.json)
        try? globalStore.vm.addImportHandler(named: "html", namespace: namespace, block: self.html)

        try? globalStore.vm.addImportHandler(named: "set_rate_limit", namespace: namespace, block: self.set_rate_limit)
        try? globalStore.vm.addImportHandler(named: "set_rate_limit_period", namespace: namespace, block: self.set_rate_limit_period)
    }
}

extension WasmNet {

    func modifyRequest(_ urlRequest: URLRequest) -> URLRequest? {
        guard let url = urlRequest.url else { return nil }
        var request = urlRequest

        // ensure a user-agent is passed
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }

        // add stored cookies
        if let cookies = HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: url) ?? [])["Cookie"] {
            var cookieString = cookies
            // keep cookies in original request
            if let oldCookie = request.value(forHTTPHeaderField: "Cookie") {
                cookieString += "; " + oldCookie
            }
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }

        return request
    }

    func performRequest(_ urlRequest: URLRequest, cloudflare: Bool = true) -> WasmResponseObject? {
        // check rate limit
        if self.isRateLimited() {
            return WasmResponseObject(statusCode: 429) // HTTP 429: too many requests
        }

        guard let request = modifyRequest(urlRequest) else { return nil }

        URLSession.shared.dataTask(with: request) { data, response, error in
            self.incrementRequest()

            let headers = ((response as? HTTPURLResponse)?.allHeaderFields as? [String: String]) ?? [:]
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1

            // check for cloudflare block
            if cloudflare && headers["Server"] == "cloudflare" && (code == 503 || code == 403) {
                DispatchQueue.main.async {
                    let request = request
                    let handler = WasmNetWebViewHandler(netModule: self, request: request)
                    handler.load()
                }
            } else {
                self.storedResponse = WasmResponseObject(data: data, response: response, error: error)
                self.semaphore.signal()
            }
        }.resume()

        self.semaphore.wait()

        let response = storedResponse
        storedResponse = nil
        return response
    }

    func isRateLimited() -> Bool {
        self.rateLimit > 0
            && self.lastRequestTime?.timeIntervalSinceNow ?? self.period < self.period
            && self.passedRequests >= self.rateLimit
    }

    func incrementRequest() {
        if self.lastRequestTime?.timeIntervalSinceNow ?? 60 < self.period {
            self.passedRequests += 1
        } else {
            self.lastRequestTime = Date()
            self.passedRequests = 1
        }
    }

    var init_request: (Int32) -> Int32 {
        { method in
            self.globalStore.requestsPointer += 1
            var req = WasmRequestObject(id: self.globalStore.requestsPointer)
            req.method = HttpMethod(rawValue: Int(method))
            self.globalStore.requests[self.globalStore.requestsPointer] = req
            return Int32(req.id)
        }
    }

    var close: (Int32) -> Void {
        { descriptor in
            guard descriptor >= 0 else { return }
            self.globalStore.requests.removeValue(forKey: descriptor)
        }
    }

    var set_url: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, length > 0 else { return }
            self.globalStore.requests[descriptor]?.URL = self.globalStore.readString(offset: value, length: length)
        }
    }

    var set_header: (Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLen, value, valueLen in
            guard descriptor >= 0, keyLen > 0 else { return }
            if let headerKey = self.globalStore.readString(offset: key, length: keyLen) {
                let headerValue = valueLen <= 0 ? nil : self.globalStore.readString(offset: value, length: valueLen)
                self.globalStore.requests[descriptor]?.headers[headerKey] = headerValue
            }
        }
    }

    var set_body: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, length > 0 else { return }
            self.globalStore.requests[descriptor]?.body = self.globalStore.readData(offset: value, length: length)
        }
    }

    var set_rate_limit: (Int32) -> Void {
        { limit in
            self.rateLimit = Int(limit)
        }
    }

    var set_rate_limit_period: (Int32) -> Void {
        { period in
            self.period = TimeInterval(period)
        }
    }

    var send: (Int32) -> Void {
        { descriptor in
            guard let request = self.globalStore.requests[descriptor] else { return }
            guard let url = URL(string: request.URL ?? "") else { return }

            var urlRequest = URLRequest(url: url)

            // set headers
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }

            // set body
            if let body = request.body { urlRequest.httpBody = body }
            switch request.method {
            case .GET: urlRequest.httpMethod = "GET"
            case .POST: urlRequest.httpMethod = "POST"
            case .HEAD: urlRequest.httpMethod = "HEAD"
            case .PUT: urlRequest.httpMethod = "PUT"
            case .DELETE: urlRequest.httpMethod = "DELETE"
            default: break
            }

            let response = self.performRequest(urlRequest, cloudflare: true)
            self.globalStore.requests[descriptor]?.response = response
        }
    }

    var get_url: (Int32) -> Int32 {
        { descriptor in
            if let url = self.globalStore.requests[descriptor]?.URL {
                return self.globalStore.storeStdValue(url)
            }
            return -1
        }
    }

    var get_data_size: (Int32) -> Int32 {
        { descriptor in
            if let data = self.globalStore.requests[descriptor]?.response?.data {
                return Int32(data.count - (self.globalStore.requests[descriptor]?.response?.bytesRead ?? 0))
            }
            return -1
        }
    }

    var get_data: (Int32, Int32, Int32) -> Void {
        { descriptor, buffer, size in
            guard descriptor >= 0, size > 0 else { return }

            if let response = self.globalStore.requests[descriptor]?.response,
               let data = response.data,
               response.bytesRead + Int(size) <= data.count {
                let result = Array(data.dropLast(data.count - Int(size) - response.bytesRead))
                self.globalStore.write(bytes: result, offset: buffer)
                self.globalStore.requests[descriptor]?.response?.bytesRead += Int(size)
            }
        }
    }

    var json: (Int32) -> Int32 {
        { descriptor in
            if let data = self.globalStore.requests[descriptor]?.response?.data,
               let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
               json is [String: Any?] || json is [Any?] {
                return self.globalStore.storeStdValue(json)
            }
            return -1
        }
    }

    var html: (Int32) -> Int32 {
        { descriptor in
            if let request = self.globalStore.requests[descriptor],
               let data = request.response?.data,
               let content = String(data: data, encoding: .utf8) {
                if let baseUri = request.response?.response?.url?.absoluteString,
                   let obj = try? SwiftSoup.parse(content, baseUri) {
                    return self.globalStore.storeStdValue(obj)
                } else if let obj = try? SwiftSoup.parse(content) {
                    return self.globalStore.storeStdValue(obj)
                }
            }
            return -1
        }
    }
}
