//
//  WasmNet.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import SwiftSoup

enum HttpMethod: Int {
    case GET = 0
    case POST = 1
    case HEAD = 2
    case PUT = 3
    case DELETE = 4
}

struct WasmRequestObject: KVCObject {
    let id: Int32
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
        globalStore.export(named: "init", namespace: namespace, block: self.init_request_wrapper)
        globalStore.export(named: "send", namespace: namespace, block: self.send_wrapper)
        globalStore.export(named: "close", namespace: namespace, block: self.close_wrapper)

        globalStore.export(named: "set_url", namespace: namespace, block: self.set_url_wrapper)
        globalStore.export(named: "set_header", namespace: namespace, block: self.set_header)
        globalStore.export(named: "set_body", namespace: namespace, block: self.set_body)

        globalStore.export(named: "get_url", namespace: namespace, block: self.get_url)
        globalStore.export(named: "get_data_size", namespace: namespace, block: self.get_data_size)
        globalStore.export(named: "get_data", namespace: namespace, block: self.get_data_wrapper)

        globalStore.export(named: "json", namespace: namespace, block: self.json)
        globalStore.export(named: "html", namespace: namespace, block: self.html)
    }
}

extension WasmNet {

    var init_request: @convention(block) (Int32) -> Int32 {
        { method in
            self.globalStore.requestsPointer += 1
            var req = WasmRequestObject(id: self.globalStore.requestsPointer)
            req.method = HttpMethod(rawValue: Int(method))
            self.globalStore.requests[self.globalStore.requestsPointer] = req
            return Int32(req.id)
        }
    }

    var init_request_wrapper: WasmWrapperReturningFunction {
        { args in
            guard args.count == 1 else { return -1 }
            if let arg1 = args[0] as? Int32 {
                return self.init_request(arg1)
            }
            return -1
        }
    }

    var close: @convention(block) (Int32) -> Void {
        { descriptor in
            guard descriptor >= 0 else { return }
            self.globalStore.requests.removeValue(forKey: descriptor)
        }
    }

    var close_wrapper: WasmWrapperVoidFunction {
        { args in
            guard args.count == 1 else { return }
            if let arg1 = args[0] as? Int32 {
                self.close(arg1)
            }
        }
    }

    var set_url: @convention(block) (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, length > 0 else { return }
            self.globalStore.requests[descriptor]?.URL = self.globalStore.readString(offset: value, length: length)
        }
    }

    var set_url_wrapper: WasmWrapperVoidFunction {
        { args in
            guard args.count == 3 else { return }
            if let arg1 = args[0] as? Int32, let arg2 = args[1] as? Int32, let arg3 = args[2] as? Int32 {
                self.set_url(arg1, arg2, arg3)
            }
        }
    }

    var set_header: @convention(block) (Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLen, value, valueLen in
            guard descriptor >= 0, keyLen > 0, valueLen > 0 else { return }
            if let headerKey = self.globalStore.readString(offset: key, length: keyLen) {
                let headerValue = self.globalStore.readString(offset: value, length: valueLen)
                self.globalStore.requests[descriptor]?.headers[headerKey] = headerValue
            }
        }
    }

    var set_body: @convention(block) (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, length > 0 else { return }
            self.globalStore.requests[descriptor]?.body = self.globalStore.readData(offset: value, length: length)
        }
    }

    var send: @convention(block) (Int32) -> Void {
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
                self.globalStore.requests[descriptor]?.data = data
                self.globalStore.requests[descriptor]?.response = response
                self.globalStore.requests[descriptor]?.error = error
                semaphore.signal()
            }.resume()

            semaphore.wait()
        }
    }

    var send_wrapper: WasmWrapperVoidFunction {
        { args in
            guard args.count == 1 else { return }
            if let arg1 = args[0] as? Int32 {
                self.send(arg1)
            }
        }
    }

    var get_url: @convention(block) (Int32) -> Int32 {
        { descriptor in
            if let url = self.globalStore.requests[descriptor]?.URL {
                return self.globalStore.storeStdValue(url)
            }
            return -1
        }
    }

    var get_data_size: @convention(block) (Int32) -> Int32 {
        { descriptor in
            if let data = self.globalStore.requests[descriptor]?.data {
                return Int32(data.count - (self.globalStore.requests[descriptor]?.bytesRead ?? 0))
            }
            return -1
        }
    }

    var get_data: @convention(block) (Int32, Int32, Int32) -> Void {
        { descriptor, buffer, size in
            guard descriptor >= 0, size > 0 else { return }

            if let request = self.globalStore.requests[descriptor],
               let data = request.data,
               request.bytesRead + Int(size) <= data.count {
                let result = Array(data.dropLast(data.count - Int(size) - request.bytesRead))
                self.globalStore.write(bytes: result, offset: buffer)
                self.globalStore.requests[descriptor]?.bytesRead += Int(size)
            }
        }
    }

    var get_data_wrapper: WasmWrapperVoidFunction {
        { args in
            guard args.count == 3 else { return }
            if let arg1 = args[0] as? Int32, let arg2 = args[1] as? Int32, let arg3 = args[2] as? Int32 {
                self.get_data(arg1, arg2, arg3)
            }
        }
    }

    var json: @convention(block) (Int32) -> Int32 {
        { descriptor in
            if let data = self.globalStore.requests[descriptor]?.data,
               let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
               json is [String: Any?] || json is [Any?] {
                return self.globalStore.storeStdValue(json)
            }
            return -1
        }
    }

    var html: @convention(block) (Int32) -> Int32 {
        { descriptor in
            if let request = self.globalStore.requests[descriptor],
               let data = request.data,
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
