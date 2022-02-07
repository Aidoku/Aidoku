//
//  WasmJson.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter

class WasmJson {
    let vm: WasmInterpreter
    let memory: WasmMemory
    
    var descriptorPointer: Int32 = -1
    var descriptors: [Int32: Any] = [:]
    var references: [Int32: [Int32]] = [:]

    init(vm: WasmInterpreter, memory: WasmMemory) {
        self.vm = vm
        self.memory = memory
    }
    
    func export() {
        try? vm.addImportHandler(named: "json_parse", namespace: "env", block: self.json_parse)
        try? vm.addImportHandler(named: "json_object", namespace: "env", block: self.json_object)
        try? vm.addImportHandler(named: "json_object_getn", namespace: "env", block: self.json_object_getn)
        try? vm.addImportHandler(named: "json_object_setn", namespace: "env", block: self.json_object_setn)
        try? vm.addImportHandler(named: "json_object_deln", namespace: "env", block: self.json_object_deln)
        try? vm.addImportHandler(named: "json_array", namespace: "env", block: self.json_array)
        try? vm.addImportHandler(named: "json_array_size", namespace: "env", block: self.json_array_size)
        try? vm.addImportHandler(named: "json_array_get", namespace: "env", block: self.json_array_get)
        try? vm.addImportHandler(named: "json_array_append", namespace: "env", block: self.json_array_append)
        try? vm.addImportHandler(named: "json_array_remove", namespace: "env", block: self.json_array_remove)
        try? vm.addImportHandler(named: "json_string", namespace: "env", block: self.json_string)
        try? vm.addImportHandler(named: "json_string_value", namespace: "env", block: self.json_string_value)
        try? vm.addImportHandler(named: "json_integer", namespace: "env", block: self.json_integer)
        try? vm.addImportHandler(named: "json_integer_value", namespace: "env", block: self.json_integer_value)
        try? vm.addImportHandler(named: "json_float", namespace: "env", block: self.json_float)
        try? vm.addImportHandler(named: "json_float_value", namespace: "env", block: self.json_float_value)
        try? vm.addImportHandler(named: "json_date_value", namespace: "env", block: self.json_date_value)
        try? vm.addImportHandler(named: "json_copy", namespace: "env", block: self.json_copy)
        try? vm.addImportHandler(named: "json_free", namespace: "env", block: self.json_free)
    }
    
    func readValue(_ descriptor: Int32) -> Any? {
        descriptors[descriptor]
    }
    
    func storeValue(_ data: Any, from: Int32? = nil) -> Int32 {
        descriptorPointer += 1
        descriptors[descriptorPointer] = data
        if let d = from {
            var refs = references[d] ?? []
            refs.append(descriptorPointer)
            references[d] = refs
        }
        return descriptorPointer
    }
    
    func removeValue(_ descriptor: Int32) {
        descriptors.removeValue(forKey: descriptor)
        for d in references[descriptor] ?? [] {
            removeValue(d)
        }
        references.removeValue(forKey: descriptor)
    }
    
    var json_parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let readData = try? self.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
               let json = try? JSONSerialization.jsonObject(with: readData, options: .fragmentsAllowed) as? [String: Any?] {
                return self.storeValue(json)
            } else if let readData = try? self.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
                      let json = try? JSONSerialization.jsonObject(with: readData, options: .fragmentsAllowed) as? [Any?] {
                return self.storeValue(json)
            }
            return -1
        }
    }
    
    var json_copy: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.readValue(json) {
                return self.storeValue(object)
            }
            return -1
        }
    }
    
    var json_free: (Int32) -> Void {
        { json in
            self.removeValue(json)
        }
    }
    
    // MARK: Object
    
    var json_object: () -> Int32 {
        {
            self.storeValue([:])
        }
    }
    
    var json_object_getn: (Int32, Int32, Int32) -> Int32 {
        { json, key, key_len in
            guard json >= 0, key >= 0 else { return -1 }
            if let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               let object = (self.readValue(json) as? [String: Any?])?[keyString] {
                return self.storeValue(object as Any, from: json)
            }
            return -1
        }
    }
    
    var json_object_setn: (Int32, Int32, Int32, Int32) -> Void {
        { json, key, key_len, value in
            guard json >= 0, key >= 0, value >= 0 else { return }
            if let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.readValue(json) as? [String: Any?],
               let valueToSet = self.readValue(value) {
                object[keyString] = valueToSet
                self.descriptors[json] = object
            }
        }
    }
    
    var json_object_deln: (Int32, Int32, Int32) -> Void {
        { json, key, key_len in
            guard json >= 0, key >= 0 else { return }
            if let keyString = try? self.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.readValue(json) as? [String: Any?] {
                object.removeValue(forKey: keyString)
                self.descriptors[json] = object
            }
        }
    }
    
    // MARK: Array
    
    var json_array: () -> Int32 {
        {
            self.storeValue([])
        }
    }
    
    var json_array_size: (Int32) -> Int32 {
        { json in
            return Int32((self.readValue(json) as? [Any])?.count ?? 0)
        }
    }
    
    var json_array_get: (Int32, Int32) -> Int32 {
        { json, index in
            guard json >= 0, index >= 0 else { return -1 }
            if let array = self.readValue(json) as? [Any] {
                guard index < array.count else { return -1 }
                let value = array[Int(index)]
                return self.storeValue(value, from: json)
            }
            return -1
        }
    }
    
    var json_array_append: (Int32, Int32) -> Void {
        { json, value in
            guard json >= 0, value >= 0 else { return }
            if var array = self.readValue(json) as? [Any],
               let valueToAppend = self.readValue(value){
                array.append(valueToAppend)
                self.descriptors[json] = array
            }
        }
    }
    
    var json_array_remove: (Int32, Int32) -> Void {
        { json, index in
            guard json >= 0, index >= 0 else { return }
            if var array = self.readValue(json) as? [Any] {
                guard index < array.count else { return }
                array.remove(at: Int(index))
                self.descriptors[json] = array
            }
        }
    }
    
    // MARK: String
    
    var json_string: (Int32, Int32) -> Int32 {
        { string, string_len in
            if let value = try? self.vm.stringFromHeap(byteOffset: Int(string), length: Int(string_len)) {
                return self.storeValue(value)
            }
            return -1
        }
    }
    
    var json_string_value: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            if let string = self.readValue(json) as? String {
                return self.vm.write(string: string, memory: self.memory)
            }
            return 0
        }
    }
    
    // MARK: Number
    
    var json_integer: (Int32) -> Int32 {
        { int in
            self.storeValue(int)
        }
    }
    
    var json_integer_value: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let int = self.readValue(json) as? Int {
                return Int32(int)
            } else if let int = Int(self.readValue(json) as? String ?? "Error") {
                return Int32(int)
            }
            return -1
        }
    }
    
    var json_float: (Float32) -> Int32 {
        { float in
            self.storeValue(float)
        }
    }
    
    var json_float_value: (Int32) -> Float32 {
        { json in
            guard json >= 0 else { return -1 }
            if let float = self.readValue(json) as? Float {
                return Float32(float)
            } else if let float = Float(self.readValue(json) as? String ?? "Error") {
                return Float32(float)
            }
            return -1
        }
    }
    
    var json_date_value: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int64 {
        { json, format, format_len, locale, locale_len, timeZone, timeZone_len in
            guard json >= 0, format_len > 0 else { return -1 }
            if let string = self.readValue(json) as? String,
               let formatString = try? self.vm.stringFromHeap(byteOffset: Int(format), length: Int(format_len)) {
                let localeString = locale_len > 0 ? (try? self.vm.stringFromHeap(byteOffset: Int(locale), length: Int(locale_len))) ?? "en_US_POSIX" : "en_US_POSIX"
                let timeZoneString = timeZone_len > 0 ? (try? self.vm.stringFromHeap(byteOffset: Int(timeZone), length: Int(timeZone_len))) ?? "UTC" : "UTC"
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: localeString)
                formatter.timeZone = TimeZone(identifier: timeZoneString)
                formatter.dateFormat = formatString
                if let date = formatter.date(from: string) {
                    return Int64(date.timeIntervalSince1970)
                }
            }
            return -1
        }
    }
}
