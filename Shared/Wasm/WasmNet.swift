//
//  WasmNet.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter
import SwiftSoup

enum HttpMethod: Int {
    case GET = 0
    case POST = 1
    case HEAD = 2
    case PUT = 3
    case DELETE = 4
}

struct WasmResponseObject: KVCObject {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    var bytesRead: Int = 0

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "data": return data != nil ? [UInt8](data!) : []
        case "headers": return (response as? HTTPURLResponse)?.allHeaderFields
        case "status_code": return (response as? HTTPURLResponse)?.statusCode
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

class WasmNet: WasmModule {

    var globalStore: WasmGlobalStore

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "net") {
        try? globalStore.vm.addImportHandler(named: "init", namespace: namespace, block: self.init_request)
        try? globalStore.vm.addImportHandler(named: "send", namespace: namespace, block: self.send)
        try? globalStore.vm.addImportHandler(named: "close", namespace: namespace, block: self.close)

        try? globalStore.vm.addImportHandler(named: "set_url", namespace: namespace, block: self.set_url)
        try? globalStore.vm.addImportHandler(named: "set_header", namespace: namespace, block: self.set_header)
        try? globalStore.vm.addImportHandler(named: "set_body", namespace: namespace, block: self.set_header)

        try? globalStore.vm.addImportHandler(named: "get_url", namespace: namespace, block: self.get_url)
        try? globalStore.vm.addImportHandler(named: "get_data_size", namespace: namespace, block: self.get_data_size)
        try? globalStore.vm.addImportHandler(named: "get_data", namespace: namespace, block: self.get_data)

        try? globalStore.vm.addImportHandler(named: "json", namespace: namespace, block: self.json)
        try? globalStore.vm.addImportHandler(named: "html", namespace: namespace, block: self.html)
    }
}

extension WasmNet {

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
            guard descriptor >= 0, keyLen > 0, valueLen > 0 else { return }
            if let headerKey = self.globalStore.readString(offset: key, length: keyLen) {
                let headerValue = self.globalStore.readString(offset: value, length: valueLen)
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

    var send: (Int32) -> Void {
        { descriptor in
            guard let request = self.globalStore.requests[descriptor] else { return }
            guard let url = URL(string: request.URL ?? "") else { return }

            let semaphore = DispatchSemaphore(value: 0)

            var urlRequest = URLRequest(url: url)
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
            switch request.method {
            case .GET: urlRequest.httpMethod = "GET"
            case .POST: urlRequest.httpMethod = "POST"
            case .HEAD: urlRequest.httpMethod = "HEAD"
            case .PUT: urlRequest.httpMethod = "PUT"
            case .DELETE: urlRequest.httpMethod = "DELETE"
            default: break
            }

            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                let response = WasmResponseObject(data: data, response: response, error: error)
                self.globalStore.requests[descriptor]?.response = response
                semaphore.signal()
            }.resume()

            semaphore.wait()
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
