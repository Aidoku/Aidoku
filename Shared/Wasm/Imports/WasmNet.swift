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
    var headers: [AnyHashable: Any]?

    var bytesRead: Int = 0

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil, statusCode: Int? = nil, headers: [AnyHashable: Any]? = nil) {
        self.data = data
        self.response = response
        self.error = error
        self.statusCode = statusCode ?? (response as? HTTPURLResponse)?.statusCode
        self.headers = headers ?? (response as? HTTPURLResponse)?.allHeaderFields
    }

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "data": return data != nil ? [UInt8](data!) : []
        case "headers": return headers != nil ? headers : (response as? HTTPURLResponse)?.allHeaderFields
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

// MARK: - Net Module
class WasmNet: WasmImports {

    var globalStore: WasmGlobalStore

    let semaphore = DispatchSemaphore(value: 0)

    var rateLimit: Int = -1 // how many requests to let through during the period
    var period: TimeInterval = 60 // seconds in the rate limit period
    var lastRequestTime: Date?
    var passedRequests: Int = 0

    var storedResponse: WasmResponseObject?

    // macOS 10.15 firefox user agent
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:107.0) Gecko/20100101 Firefox/107.0"

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
        try? globalStore.vm.addImportHandler(named: "get_header", namespace: namespace, block: self.get_header)
        try? globalStore.vm.addImportHandler(named: "get_status_code", namespace: namespace, block: self.get_status_code)

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
            if cloudflare && headers["Server"] == "cloudflare" && (code == 503 || code == 403 || code == 429) {
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
            && -(self.lastRequestTime?.timeIntervalSinceNow ?? -self.period) < self.period
            && self.passedRequests >= self.rateLimit
    }

    func incrementRequest() {
        if let lastRequestTime = self.lastRequestTime, -lastRequestTime.timeIntervalSinceNow < self.period {
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
            let url: URL?
            // iOS 17 encodes by default the url string causing double encoded characters
            if #available(iOS 17.0, *) {
                // it seems if we pass a valid RFC 3986 url string to URL() it behaves the same as on iOS 16
                let urlEncoded = request.URL?
                    .removingPercentEncoding?
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                url = URL(string: urlEncoded ?? "", encodingInvalidCharacters: false)
            } else {
                url = URL(string: request.URL ?? "")
            }
            guard let url else { return }

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

    var get_header: (Int32, Int32, Int32) -> Int32 {
        { descriptor, field, length in
            guard descriptor >= 0, length > 0 else { return -1 }
            if let response = self.globalStore.requests[descriptor]?.response?.response as? HTTPURLResponse,
               let field = self.globalStore.readString(offset: field, length: length),
               let value = response.value(forHTTPHeaderField: field) {
                return self.globalStore.storeStdValue(value)
            }
            return -1
        }
    }

    var get_status_code: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let statusCode = self.globalStore.requests[descriptor]?.response?.statusCode {
                return Int32(statusCode)
            }
            return -1
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
            if let request = self.globalStore.requests[descriptor], let data = request.response?.data {
                var content = String(decoding: data, as: UTF8.self)
                if content.isEmpty {
                    content = String(data: data, encoding: .ascii) ?? content
                }
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
