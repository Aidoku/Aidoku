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
    
    var jsonPointer: Int32 = 1
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
    
//    func writeJsonString(_ string: String) -> Int32 {
//        var data = string.int32Array
//        data.insert(Int32(string.utf8.count), at: 0)
//        data.insert(WasmJsonTypes.string.rawValue, at: 0)
//        return self.vm.write(data: data)
//    }
//
//    func writeJsonInt(_ int: Int) -> Int32 {
//        self.vm.write(data: [WasmJsonTypes.int.rawValue, Int32(int)])
//    }
    
//    func writeJsonArray(_ array: [Any]) -> Int32 {
//        var data = array.map { self.writeJsonValue($0) }
//        data.insert(Int32(data.count), at: 0)
//        data.insert(WasmJsonTypes.array.rawValue, at: 0)
//        return self.vm.write(data: data)
//    }
    
//    func writeJsonValue(_ value: Any?) -> Int32 {
//        var pointer: Int32 = 0
//        if let string = value as? String {
//            pointer = self.writeJsonString(string)
//        } else if let int = value as? Int {
//            pointer = self.writeJsonInt(int)
//        } else if let dict = value as? [String: Any] {
//            pointer = self.writeJsonDict(dict)
//        } else if let arr = value as? [Any] {
//            pointer = self.writeJsonArray(arr)
//        }
//        return pointer
//    }
    
//    func writeJsonDict(_ dictionary: [String: Any]) -> Int32 {
//        var lastDictPointer: Int32 = 0
//        for key in dictionary.keys.reversed() {
//            let keyPointer = self.writeJsonString(key)
//            let valuePointer = self.writeJsonValue(dictionary[key])
//            lastDictPointer = self.vm.write(data: [WasmJsonTypes.dictionary.rawValue, keyPointer, valuePointer, lastDictPointer])
//        }
//        return lastDictPointer
//        print("writeJsonDict")
//    }
    
//    func readJsonDictValue(_ dictionary: Int32, key: String) -> Any {
//        let dictValues: [Int32] = try! self.vm.valuesFromHeap(byteOffset: Int(dictionary), length: 4)
//        let keyValues: [Int32] = try! self.vm.valuesFromHeap(byteOffset: Int(dictValues[1]), length: 4)
//        let stringBytes: [UInt8] = try! self.vm.bytesFromHeap(byteOffset: Int(dictValues[1] + 8), length: Int(keyValues[1]))
//        let string = String(stringBytes.map(UnicodeScalar.init).map(Character.init))
//        if string == key {
////            print("returning \(dictValues[2]) for \(string)")
//            return dictValues[2]
//        } else if dictValues[3] == 0 {
//            return 0
//        } else {
//            return readJsonDictValue(dictValues[3], key: key)
//        }
//    }
    
//    func readJsonArrayValue(_ array: Int32, pos: Int) -> Int32 {
//        let val: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(array) + pos * 4 + 8)
//        print("array[\(pos)] = \(val)")
//        return val
//    }
    
//    func findJsonDictInArrayWith(_ array: Int32, key: String, value: Int32) -> Int32 {
//        let valueType: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(value))
//        var pos = 0
//        var done = false
//        var pointer: Int32 = 0
//        while !done {
//            let val: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(array) + pos * 4 + 8)
//            let values: [Int32]? = try? self.vm.valuesFromHeap(byteOffset: Int(val), length: 4)
//            if let values = values, values[0] == WasmJsonTypes.dictionary.rawValue {
//                let dictValue = writeJsonValue(readJsonDictValue(val, key: key))
//                let objValues: [Int32] = try! self.vm.valuesFromHeap(byteOffset: Int(dictValue), length: 4)
//                if objValues[0] == valueType {
//                    switch valueType {
//                    case WasmJsonTypes.string.rawValue:
//                        let objValue = self.vm.stringFromHeap(byteOffset: Int(dictValue + 8))
//                        let keyValue = self.vm.stringFromHeap(byteOffset: Int(value + 8))
//                        if objValue == keyValue {
//                            pointer = val
//                            done = true
//                        }
//                    case WasmJsonTypes.int.rawValue:
//                        let objValue: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(dictValue + 4))
//                        let keyValue: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(value + 4))
//                        if objValue == keyValue {
//                            pointer = val
//                            done = true
//                        }
//                    default:
//                        break
//                    }
//                }
//                pos += 1
//            } else {
//                done = true
//            }
//        }
//        return pointer
//    }
    
    var json_parse: (Int32, Int32) -> Int32 {
        { data, size in
            if let readData = try? self.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)) {
                let json = (try? JSONSerialization.jsonObject(with: readData, options: .allowFragments) as? [String: Any]) ?? [:]
                return self.writeJsonData(json)
            }
            return 0
//            let dictOffset = self.writeJsonDict(json)
//            return Int32(dictOffset)
        }
    }
    
    var json_dictionary_get: (Int32, Int32) -> Int32 {
        { dict, key in
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            return self.writeJsonData((self.readJsonData(dict) as? [String: Any])?[keyString] ?? "")
//            return self.writeJsonValue(self.readJsonDictValue(dict, key: keyString))
        }
    }
    
    var json_dictionary_get_string: (Int32, Int32) -> Int32 {
        { dict, key in
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            let str = ((self.readJsonData(dict) as? [String: Any])?[keyString] as? String) ?? ""
            return self.vm.write(string: str)
//            return self.vm.write(string: self.readJsonDictValue(dict, key: keyString) as? String ?? "")
        }
    }
    
    var json_array_get: (Int32, Int32) -> Int32 {
        { arr, pos in
            return self.writeJsonData((self.readJsonData(arr) as? [Any])?[Int(pos)] ?? "")
//            return self.readJsonArrayValue(arr, pos: Int(pos))
        }
    }
    
    var json_array_get_length: (Int32) -> Int32 {
        { arr in
            return Int32((self.readJsonData(arr) as? [Any])?.count ?? 0)
//            Int32(self.jsonArrayParses[arr]?.count ?? 0)
        }
    }
    
    
    var json_array_find_dictionary: (Int32, Int32, Int32) -> Int32 {
        { arr, key, value in
            let keyString = self.vm.stringFromHeap(byteOffset: Int(key))
            let valueString = self.vm.stringFromHeap(byteOffset: Int(value))
//            return self.findJsonDictInArrayWith(arr, key: keyString, value: value)
            let array = self.readJsonData(arr) as? [[String: Any]] ?? []
            let index = array.firstIndex { $0[keyString] as? String == valueString }
            if let index = index {
                return self.writeJsonData(array[index])
            }
            return 0
        }
    }
    
//    func freeObject(_ pointer: Int32, log: Int = 0) {
//        let type: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(pointer))
//        switch type {
//        case WasmJsonTypes.string.rawValue:
//            break
//        case WasmJsonTypes.int.rawValue:
//            break
//        case WasmJsonTypes.dictionary.rawValue:
//            let dictValues: [Int32] = try! self.vm.valuesFromHeap(byteOffset: Int(pointer), length: 4)
//            WasmManager.shared.memory.free(dictValues[1]) // key
//            if dictValues[2] > 0 {
////                print(self.vm.stringFromHeap(byteOffset: Int(dictValues[1]) + 8))
//                freeObject(dictValues[2], log: 2) // value
//            }
//            if dictValues[3] > 0 {
//                freeObject(dictValues[3], log: 1) // next entry
//            }
//        case WasmJsonTypes.array.rawValue:
//            let length: Int32 = try! self.vm.valueFromHeap(byteOffset: Int(pointer) + 4)
//            for i in 0..<length {
//                let address = pointer + 8 + i * 4
//                if address > 0 {
//                    freeObject(address, log: Int(50 + log))
//                }
//            }
//        default:
//            return freeObject(type)
//        }
//        WasmManager.shared.memory.free(pointer)
//    }
    
    var json_free: (Int32) -> Void {
        { dict in
            self.jsonData.removeValue(forKey: dict)
        }
    }
}
