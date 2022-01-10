//
//  WasmRequest.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WebAssembly

struct WasmRequestObject {
    let id: Int
    var URL: String?
    var method: String?
    var headers: [String]?
    var bodyLength: Int?
    var body: Data?
    
    var data: Data?
}

class WasmRequest {
    let vm: Interpreter
    let memory: WasmMemory
    var requests: [WasmRequestObject] = []
    
    init(vm: Interpreter, memory: WasmMemory) {
        self.vm = vm
        self.memory = memory
    }
    
    var request_init: () -> Int32 {
        {
            let req = WasmRequestObject(id: self.requests.count)
            self.requests.append(req)
            return Int32(req.id)
        }
    }
    
    var request_set: (Int32, Int32, Int32) -> Void {
        { req, opt, val in
            let stringValue = self.vm.stringFromHeap(byteOffset: Int(val))
            switch opt {
            case 0: // REQ_URL
                self.requests[Int(req)].URL = stringValue
            case 1: // REQ_METHOD
                self.requests[Int(req)].method = stringValue
            case 2: // REQ_HEADERS
                self.requests[Int(req)].headers = stringValue.split(whereSeparator: \.isNewline).map { String($0) }
            case 3: // REQ_BODY_LENGTH
                let intValue: Int32 = (try? self.vm.valueFromHeap(byteOffset: Int(val))) ?? 0
                self.requests[Int(req)].bodyLength = Int(intValue)
            case 4: // REQ_BODY
                let dataValue = try? self.vm.dataFromHeap(byteOffset: Int(val), length: self.requests[Int(req)].bodyLength ?? 0)
                self.requests[Int(req)].body = dataValue
            default:
                break
            }
        }
    }
    
    var request_data: (Int32, Int32) -> Int32 {
        { req, size in
            let semaphore = DispatchSemaphore(value: 0)
            
            let request = self.requests[Int(req)]
            guard let url = URL(string: request.URL ?? "") else {
                return -1
            }
            
            var urlRequest = URLRequest(url: url)
            for value in request.headers ?? [] {
                urlRequest.setValue(value, forHTTPHeaderField: "key")
            }
            if let body = request.body { urlRequest.httpBody = body }
            if let method = request.method { urlRequest.httpMethod = method }
            
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let data = data {
                    self.requests[Int(req)].data = data
                }
                semaphore.signal()
            }.resume()
            
            semaphore.wait()
            
            var dataPointer: Int32 = -1
            
            if let data = self.requests[Int(req)].data {
                let dataArray = Array(data)
                
                dataPointer = self.memory.malloc(Int32(dataArray.count))
                try? self.vm.writeToHeap(bytes: dataArray, byteOffset: Int(dataPointer))
                try? self.vm.writeToHeap(values: [Int32(dataArray.count)], byteOffset: Int(size))
            }
            
            self.requests.remove(at: Int(req))
            
            return dataPointer
        }
    }
}
