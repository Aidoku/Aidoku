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
    var pointer: Int32?
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
            default:
                break
            }
        }
    }
    
    var request_data: (Int32, Int32) -> Int32 {
        { req, size in
            let semaphore = DispatchSemaphore(value: 0)
            
            let request = self.requests[Int(req)]
            
            guard let url = request.URL else {
                return 0
            }
            
            URLSession.shared.dataTask(with: URLRequest.from(URL(string: url)!)) { data, response, error in
                if let data = data {
                    self.requests[Int(req)].data = data
                }
                semaphore.signal()
            }.resume()
            
            semaphore.wait()
            
            let data = self.requests[Int(req)].data!
            let dataArray = Array(data)
            
            let dataPointer = self.memory.malloc(Int32(dataArray.count))
            try? self.vm.writeToHeap(data: data, byteOffset: Int(dataPointer))
            try? self.vm.writeToHeap(values: [Int32(dataArray.count)], byteOffset: Int(size))
            
            _ = self.requests.popLast()
            
            return dataPointer
        }
    }
}
