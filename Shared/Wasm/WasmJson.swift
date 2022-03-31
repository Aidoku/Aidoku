//
//  WasmJson.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter

class WasmJson {

    var globalStore: WasmGlobalStore

    enum JsonType: Int {
        case null = 0
        case int = 1
        case float = 2
        case string = 3
        case bool = 4
        case array = 5
        case object = 6
    }

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "json") {
        try? globalStore.vm.addImportHandler(named: "json_parse", namespace: namespace, block: self.json_parse)
        try? globalStore.vm.addImportHandler(named: "json_copy", namespace: namespace, block: self.json_copy)
        try? globalStore.vm.addImportHandler(named: "json_destroy", namespace: namespace, block: self.json_destroy)

        try? globalStore.vm.addImportHandler(named: "json_create_null", namespace: namespace, block: self.json_create_null)
        try? globalStore.vm.addImportHandler(named: "json_create_int", namespace: namespace, block: self.json_create_int)
        try? globalStore.vm.addImportHandler(named: "json_create_float", namespace: namespace, block: self.json_create_float)
        try? globalStore.vm.addImportHandler(named: "json_create_string", namespace: namespace, block: self.json_create_string)
        try? globalStore.vm.addImportHandler(named: "json_create_bool", namespace: namespace, block: self.json_create_bool)
        try? globalStore.vm.addImportHandler(named: "json_create_array", namespace: namespace, block: self.json_create_array)
        try? globalStore.vm.addImportHandler(named: "json_create_object", namespace: namespace, block: self.json_create_object)

        try? globalStore.vm.addImportHandler(named: "json_typeof", namespace: namespace, block: self.json_typeof)
        try? globalStore.vm.addImportHandler(named: "json_string_len", namespace: namespace, block: self.json_string_len)
        try? globalStore.vm.addImportHandler(named: "json_read_string", namespace: namespace, block: self.json_read_string)
        try? globalStore.vm.addImportHandler(named: "json_read_int", namespace: namespace, block: self.json_read_int)
        try? globalStore.vm.addImportHandler(named: "json_read_float", namespace: namespace, block: self.json_read_float)
        try? globalStore.vm.addImportHandler(named: "json_read_bool", namespace: namespace, block: self.json_read_bool)

        try? globalStore.vm.addImportHandler(named: "json_object_len", namespace: namespace, block: self.json_object_len)
        try? globalStore.vm.addImportHandler(named: "json_object_get", namespace: namespace, block: self.json_object_get)
        try? globalStore.vm.addImportHandler(named: "json_object_set", namespace: namespace, block: self.json_object_set)
        try? globalStore.vm.addImportHandler(named: "json_object_remove", namespace: namespace, block: self.json_object_remove)
        try? globalStore.vm.addImportHandler(named: "json_object_keys", namespace: namespace, block: self.json_object_keys)
        try? globalStore.vm.addImportHandler(named: "json_object_values", namespace: namespace, block: self.json_object_values)

        try? globalStore.vm.addImportHandler(named: "json_array_len", namespace: namespace, block: self.json_array_len)
        try? globalStore.vm.addImportHandler(named: "json_array_get", namespace: namespace, block: self.json_array_get)
        try? globalStore.vm.addImportHandler(named: "json_array_set", namespace: namespace, block: self.json_array_set)
        try? globalStore.vm.addImportHandler(named: "json_array_append", namespace: namespace, block: self.json_array_append)
        try? globalStore.vm.addImportHandler(named: "json_array_remove", namespace: namespace, block: self.json_array_remove)

    }

    func readValue(_ descriptor: Int32) -> Any? {
        globalStore.jsonDescriptors[descriptor] as Any?
    }

    func storeValue(_ data: Any?, from: Int32? = nil) -> Int32 {
        globalStore.jsonDescriptorPointer += 1
        globalStore.jsonDescriptors[globalStore.jsonDescriptorPointer] = data
        if let d = from {
            var refs = globalStore.jsonReferences[d] ?? []
            refs.append(globalStore.jsonDescriptorPointer)
            globalStore.jsonReferences[d] = refs
        }
        return globalStore.jsonDescriptorPointer
    }

    func removeValue(_ descriptor: Int32) {
        globalStore.jsonDescriptors.removeValue(forKey: descriptor)
        for d in globalStore.jsonReferences[descriptor] ?? [] {
            removeValue(d)
        }
        globalStore.jsonReferences.removeValue(forKey: descriptor)
    }
}

extension WasmJson {

    var json_parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let readData = try? self.globalStore.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
               let json = try? JSONSerialization.jsonObject(with: readData, options: .fragmentsAllowed) as? [String: Any?] {
                return self.storeValue(json)
            } else if let readData = try? self.globalStore.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
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

    var json_destroy: (Int32) -> Void {
        { json in
            self.removeValue(json)
        }
    }
}

// MARK: - Create
extension WasmJson {

    var json_create_null: () -> Int32 {
        {
            self.storeValue(-1)
        }
    }

    var json_create_int: (Int32) -> Int32 {
        { int in
            self.storeValue(int)
        }
    }

    var json_create_float: (Float32) -> Int32 {
        { float in
            self.storeValue(float)
        }
    }

    var json_create_string: (Int32, Int32) -> Int32 {
        { string, string_len in
            if let value = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(string), length: Int(string_len)) {
                return self.storeValue(value)
            }
            return -1
        }
    }

    var json_create_bool: (Int32) -> Int32 {
        { bool in
            self.storeValue(bool != 0)
        }
    }

    var json_create_object: () -> Int32 {
        {
            self.storeValue([:])
        }
    }

    var json_create_array: () -> Int32 {
        {
            self.storeValue([])
        }
    }
}

// MARK: - Read
extension WasmJson {

    var json_typeof: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            let value = self.readValue(json)
            if value is Int {
                return Int32(JsonType.int.rawValue)
            } else if value is Float {
                return Int32(JsonType.float.rawValue)
            } else if value is String {
                return Int32(JsonType.string.rawValue)
            } else if value is Bool {
                return Int32(JsonType.bool.rawValue)
            } else if value is [Any] {
                return Int32(JsonType.array.rawValue)
            } else if value is [String: Any] {
                return Int32(JsonType.object.rawValue)
            }
            return -1
        }
    }

    var json_string_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let string = self.readValue(json) as? String {
                return Int32(string.utf8.count)
            }
            return -1
        }
    }

    var json_read_string: (Int32, Int32, Int32) -> Void {
        { json, buffer, size in
            guard json >= 0, size >= 0 else { return }
            if let string = self.readValue(json) as? String, Int(size) < string.utf8.count {
                try? self.globalStore.vm.writeToHeap(
                    values: string.utf8.dropLast(string.utf8.count - Int(size)).chunked(into: 4).map {
                        Int32(truncatingIfNeeded: UInt32($0.reversed()))
                    },
                    byteOffset: Int(buffer)
                )
            }
        }
    }

    var json_read_int: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            if let int = self.readValue(json) as? Int {
                return Int32(int)
            } else if let int = Int(self.readValue(json) as? String ?? "Error") {
                return Int32(int)
            }
            return 0
        }
    }

    var json_read_float: (Int32) -> Float32 {
        { json in
            guard json >= 0 else { return 0 }
            if let float = self.readValue(json) as? Float {
                return Float32(float)
            } else if let float = Float(self.readValue(json) as? String ?? "Error") {
                return Float32(float)
            }
            return 0
        }
    }

    var json_read_bool: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            if let bool = self.readValue(json) as? Bool {
                return Int32(bool ? 1 : 0)
            } else if let int = self.readValue(json) as? Int {
                return Int32(int != 0 ? 1 : 0)
            }
            return 0
        }
    }
}

// MARK: - Object
extension WasmJson {

    var json_object_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            return Int32((self.readValue(json) as? [String: Any?])?.count ?? 0)
        }
    }

    var json_object_get: (Int32, Int32, Int32) -> Int32 {
        { json, key, keyLength in
            guard json >= 0, key >= 0, keyLength > 0 else { return -1 }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(keyLength)),
               let object = (self.readValue(json) as? [String: Any?])?[keyString] {
                return self.storeValue(object as Any, from: json)
            }
            return -1
        }
    }

    var json_object_set: (Int32, Int32, Int32, Int32) -> Void {
        { json, key, key_len, value in
            guard json >= 0, key >= 0, value >= 0 else { return }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.readValue(json) as? [String: Any?],
               let valueToSet = self.readValue(value) {
                object[keyString] = valueToSet
                self.globalStore.jsonDescriptors[json] = object
            }
        }
    }

    var json_object_remove: (Int32, Int32, Int32) -> Void {
        { json, key, key_len in
            guard json >= 0, key >= 0 else { return }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.readValue(json) as? [String: Any?] {
                object.removeValue(forKey: keyString)
                self.globalStore.jsonDescriptors[json] = object
            }
        }
    }

    var json_object_keys: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.readValue(json) as? [String: Any?] {
                return self.storeValue(Array(object.keys), from: json)
            }
            return -1
        }
    }

    var json_object_values: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.readValue(json) as? [String: Any] {
                return self.storeValue(Array(object.values), from: json)
            }
            return -1
        }
    }
}

// MARK: - Array
extension WasmJson {

    var json_array_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            return Int32((self.readValue(json) as? [Any?])?.count ?? 0)
        }
    }

    var json_array_get: (Int32, Int32) -> Int32 {
        { json, index in
            guard json >= 0, index >= 0 else { return -1 }
            if let array = self.readValue(json) as? [Any?] {
                guard index < array.count else { return -1 }
                let value = array[Int(index)]
                return self.storeValue(value, from: json)
            }
            return -1
        }
    }

    var json_array_set: (Int32, Int32, Int32) -> Void {
        { json, index, value in
            guard json >= 0, value >= 0, index >= 0 else { return }
            if var array = self.readValue(json) as? [Any?],
               let valueToSet = self.readValue(value),
               index < array.count {
                array[Int(index)] = valueToSet
                self.globalStore.jsonDescriptors[json] = array
            }
        }
    }

    var json_array_append: (Int32, Int32) -> Void {
        { json, value in
            guard json >= 0, value >= 0 else { return }
            if var array = self.readValue(json) as? [Any?],
               let valueToAppend = self.readValue(value) {
                array.append(valueToAppend)
                self.globalStore.jsonDescriptors[json] = array
            }
        }
    }

    var json_array_remove: (Int32, Int32) -> Void {
        { json, index in
            guard json >= 0, index >= 0 else { return }
            if var array = self.readValue(json) as? [Any?] {
                guard index < array.count else { return }
                array.remove(at: Int(index))
                self.globalStore.jsonDescriptors[json] = array
            }
        }
    }
}

// TODO: move this
// extension WasmJson {
//
//    let defaultLocale = "en_US_POSIX"
//    let defaultTimeZone = "UTC"
//
//    var json_date_value: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int64 {
//        { json, format, format_len, locale, locale_len, timeZone, timeZone_len in
//            guard json >= 0, format_len > 0 else { return -1 }
//            if let string = self.readValue(json) as? String,
//               let formatString = try? self.vm.stringFromHeap(byteOffset: Int(format), length: Int(format_len)) {
//                let localeString = locale_len > 0 ? (try? self.vm.stringFromHeap(
//                    byteOffset: Int(locale),
//                    length: Int(locale_len))
//                ) ?? self.defaultLocale : self.defaultLocale
//                let timeZoneString = timeZone_len > 0 ? (try? self.vm.stringFromHeap(
//                    byteOffset: Int(timeZone),
//                    length: Int(timeZone_len))
//                ) ?? self.defaultTimeZone : self.defaultTimeZone
//
//                let formatter = DateFormatter()
//                formatter.locale = Locale(identifier: localeString)
//                formatter.timeZone = TimeZone(identifier: timeZoneString)
//                formatter.dateFormat = formatString
//                if let date = formatter.date(from: string) {
//                    return Int64(date.timeIntervalSince1970)
//                }
//            }
//            return -1
//        }
//    }
// }
