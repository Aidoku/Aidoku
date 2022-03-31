//
//  WasmNet.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter

struct WasmRequestObject {
    let id: Int
    var URL: String?
    var method: String?
    var headers: [String: String?] = [:]
    var body: Data?

    var data: Data?
    var bytesRead: Int = 0
}

class WasmNet: WasmModule {

    var globalStore: WasmGlobalStore

    enum HttpMethod: Int {
        case GET = 0
        case POST = 1
        case HEAD = 2
        case PUT = 3
        case DELETE = 4
    }

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "net") {
        try? globalStore.vm.addImportHandler(named: "init", namespace: namespace, block: self.init_request)
        try? globalStore.vm.addImportHandler(named: "set_url", namespace: namespace, block: self.set_url)
        try? globalStore.vm.addImportHandler(named: "set_header", namespace: namespace, block: self.set_header)
        try? globalStore.vm.addImportHandler(named: "set_body", namespace: namespace, block: self.set_header)
        try? globalStore.vm.addImportHandler(named: "send", namespace: namespace, block: self.send)
        try? globalStore.vm.addImportHandler(named: "get_data_size", namespace: namespace, block: self.get_data_size)
        try? globalStore.vm.addImportHandler(named: "get_data", namespace: namespace, block: self.get_data)
        try? globalStore.vm.addImportHandler(named: "close", namespace: namespace, block: self.close)
        try? globalStore.vm.addImportHandler(named: "json", namespace: namespace, block: self.json)
    }
}

extension WasmNet {

    var init_request: (Int32) -> Int32 {
        { method in
            var req = WasmRequestObject(id: self.globalStore.requests.count)
            switch HttpMethod(rawValue: Int(method)) {
            case .GET: req.method = "GET"
            case .POST: req.method = "POST"
            case .HEAD: req.method = "HEAD"
            case .PUT: req.method = "PUT"
            case .DELETE: req.method = "DELETE"
            default: req.method = "GET"
            }
            self.globalStore.requests.append(req)
            return Int32(req.id)
        }
    }

    var set_url: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, length > 0 else { return }
            self.globalStore.requests[Int(descriptor)].URL = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(value), length: Int(length))
        }
    }

    var set_header: (Int32, Int32, Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLength, value, valueLength in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, keyLength > 0, valueLength > 0 else { return }
            if let headerKey = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(keyLength)) {
                let headerValue = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(value), length: Int(valueLength))
                self.globalStore.requests[Int(descriptor)].headers[headerKey] = headerValue
            }
        }
    }

    var set_body: (Int32, Int32, Int32) -> Void {
        { descriptor, value, length in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count, length > 0 else { return }
            self.globalStore.requests[Int(descriptor)].body = try? self.globalStore.vm.dataFromHeap(byteOffset: Int(value), length: Int(length))
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
            if let method = request.method { urlRequest.httpMethod = method }

            URLSession.shared.dataTask(with: urlRequest) { data, _, _ in
                if let data = data {
                    self.globalStore.requests[Int(descriptor)].data = data
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()
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
                try? self.globalStore.vm.writeToHeap(bytes: result, byteOffset: Int(buffer))
                self.globalStore.requests[Int(descriptor)].bytesRead += Int(size)
            }
        }
    }

    var close: (Int32) -> Void {
        { descriptor in
            guard descriptor >= 0, descriptor < self.globalStore.requests.count else { return }
            self.globalStore.requests.remove(at: Int(descriptor))
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
}
