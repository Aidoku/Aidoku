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

struct WasmRequestObject: KVCObject {
    let id: Int
    var URL: String?
    var method: HttpMethod?
    var headers: [String: String?] = [:]
    var body: Data?

    var data: Data?
    var response: URLResponse?
    var error: Error?
    var bytesRead: Int = 0

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "url": return URL
        case "method": return method?.rawValue
        case "headers": return headers
        case "body": return body
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
            var req = WasmRequestObject(id: self.globalStore.requests.count)
            req.method = HttpMethod(rawValue: Int(method))
            self.globalStore.requests.append(req)
            return Int32(req.id)
        }
    }

    var close: (Int32) -> Void {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return }
            self.globalStore.requests.remove(at: Int(descriptor))
        }
    }

    var set_url: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, length > 0 else { return }
            self.globalStore.requests[Int(descriptor)].URL = self.globalStore.readString(offset: value, length: length)
        }
    }

    var set_header: (Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLength, value, valueLength in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, keyLength > 0, valueLength > 0 else { return }
            if let headerKey = self.globalStore.readString(offset: key, length: keyLength) {
                let headerValue = self.globalStore.readString(offset: value, length: valueLength)
                self.globalStore.requests[Int(descriptor)].headers[headerKey] = headerValue
            }
        }
    }

    var set_body: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, length > 0 else { return }
            self.globalStore.requests[Int(descriptor)].body = self.globalStore.readData(offset: value, length: length)
        }
    }

    var send: (Int32) -> Void {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return }
            let semaphore = DispatchSemaphore(value: 0)

            let request = self.globalStore.requests[Int(descriptor)]
            guard let url = URL(string: request.URL ?? "") else { return }

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
                self.globalStore.requests[Int(descriptor)].data = data
                self.globalStore.requests[Int(descriptor)].response = response
                self.globalStore.requests[Int(descriptor)].error = error
                semaphore.signal()
            }.resume()

            semaphore.wait()
        }
    }

    var get_url: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return -1 }
            return self.globalStore.storeStdValue(self.globalStore.requests[Int(descriptor)].URL)
        }
    }

    var get_data_size: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return -1 }

            if let data = self.globalStore.requests[Int(descriptor)].data {
                return Int32(data.count - self.globalStore.requests[Int(descriptor)].bytesRead)
            }

            return -1
        }
    }

    var get_data: (Int32, Int32, Int32) -> Void {
        { descriptor, buffer, size in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, size > 0 else { return }

            let bytesRead = self.globalStore.requests[Int(descriptor)].bytesRead

            if let data = self.globalStore.requests[Int(descriptor)].data,
               bytesRead + Int(size) <= data.count {
                let result = Array(data.dropLast(data.count - Int(size) - bytesRead))
                self.globalStore.write(bytes: result, offset: buffer)
                self.globalStore.requests[Int(descriptor)].bytesRead += Int(size)
            }
        }
    }

    var json: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return -1 }

            if let data = self.globalStore.requests[Int(descriptor)].data,
               let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
               json is [String: Any?] || json is [Any?] {
                return self.globalStore.storeStdValue(json)
            }

            return -1
        }
    }

    var html: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return -1 }

            let request = self.globalStore.requests[Int(descriptor)]
            if let data = request.data,
               let content = String(data: data, encoding: .utf8) {
                if let baseUri = request.response?.url?.absoluteString,
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
