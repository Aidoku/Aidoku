//
//  WasmJson.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WebAssembly

enum WasmJsonTypes: Int32 {
    case string = 1, int, bool, array, dictionary
}

class WasmJson {
    let vm: Interpreter
    let memory: WasmMemory
    
    var jsonPointer: Int32 = 0
    var jsonData: [Int32: Any] = [:]
    
    init(vm: Interpreter, memory: WasmMemory) {
        self.vm = vm
        self.memory = memory
    }
    
    func readJsonData(_ descriptor: Int32) -> Any {
        jsonData[descriptor] ?? ""
    }
    
    func writeJsonData(_ data: Any) -> Int32 {
        jsonPointer += 1
        jsonData[jsonPointer] = data
        return jsonPointer
    }
    
    var json_parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let readData = try? self.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
               let json = try? JSONSerialization.jsonObject(with: readData, options: .fragmentsAllowed) as? [String: Any?] {
                return self.writeJsonData(json)
            }
            return -1
        }
    }
    
    var json_dictionary_get: (Int32, Int32) -> Int32 {
        { dict, key in
            guard dict > 0, key > 0 else { return -1 }
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            if let object = (self.readJsonData(dict) as? [String: Any?])?[keyString] {
                return self.writeJsonData(object as Any)
            }
            return -1
        }
    }
    
    var json_dictionary_get_string: (Int32, Int32) -> Int32 {
        { dict, key in
            guard dict > 0, key > 0 else { return -1 }
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            if let str = ((self.readJsonData(dict) as? [String: Any?])?[keyString] as? String) {
                return self.vm.write(string: str)
            }
            return -1
        }
    }
    
    var json_dictionary_get_int: (Int32, Int32) -> Int32 {
        { dict, key in
            guard dict > 0, key > 0 else { return -1 }
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            let int: String? = (self.readJsonData(dict) as? [String: Any?])?[keyString] as? String
            return Int32(int ?? "0") ?? 0
        }
    }
    
    var json_dictionary_get_float: (Int32, Int32) -> Float32 {
        { dict, key in
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            return Float32(((self.readJsonData(dict) as? [String: Any?])?[keyString] as? String) ?? "0") ?? 0
        }
    }
    
    var json_array_get: (Int32, Int32) -> Int32 {
        { arr, pos in
            return self.writeJsonData((self.readJsonData(arr) as? [Any])?[Int(pos)] ?? "")
        }
    }
    
    var json_array_get_string: (Int32, Int32) -> Int32 {
        { arr, pos in
            let str = (self.readJsonData(arr) as? [Any])?[Int(pos)] as? String ?? ""
            return self.vm.write(string: str)
        }
    }
    
    var json_array_get_length: (Int32) -> Int32 {
        { arr in
            return Int32((self.readJsonData(arr) as? [Any])?.count ?? 0)
        }
    }
    
    
    var json_array_find_dictionary: (Int32, Int32, Int32) -> Int32 {
        { arr, key, value in
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            let valueString = self.vm.stringFromHeap(byteOffset: Int(value))
            let array = self.readJsonData(arr) as? [[String: Any?]] ?? []
            let index = array.firstIndex { $0[keyString] as? String == valueString }
            if let index = index {
                return self.writeJsonData(array[index])
            }
            return 0
        }
    }
    
    var json_free: (Int32) -> Void {
        { dict in
            self.jsonData.removeValue(forKey: dict)
        }
    }
}
