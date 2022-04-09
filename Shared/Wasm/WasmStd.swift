//
//  WasmStd.swift
//  Aidoku
//
//  Created by Skitty on 3/31/22.
//

import Foundation

class WasmStd: WasmModule {

    var globalStore: WasmGlobalStore

    enum ObjectType: Int {
        case null = 0
        case int = 1
        case float = 2
        case string = 3
        case bool = 4
        case array = 5
        case object = 6
        case date = 7
    }

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "std") {
        try? globalStore.vm.addImportHandler(named: "copy", namespace: namespace, block: self.copy)
        try? globalStore.vm.addImportHandler(named: "destroy", namespace: namespace, block: self.destroy)

        try? globalStore.vm.addImportHandler(named: "create_null", namespace: namespace, block: self.create_null)
        try? globalStore.vm.addImportHandler(named: "create_int", namespace: namespace, block: self.create_int)
        try? globalStore.vm.addImportHandler(named: "create_float", namespace: namespace, block: self.create_float)
        try? globalStore.vm.addImportHandler(named: "create_string", namespace: namespace, block: self.create_string)
        try? globalStore.vm.addImportHandler(named: "create_bool", namespace: namespace, block: self.create_bool)
        try? globalStore.vm.addImportHandler(named: "create_array", namespace: namespace, block: self.create_array)
        try? globalStore.vm.addImportHandler(named: "create_object", namespace: namespace, block: self.create_object)
        try? globalStore.vm.addImportHandler(named: "create_date", namespace: namespace, block: self.create_date)

        try? globalStore.vm.addImportHandler(named: "typeof", namespace: namespace, block: self.typeof)
        try? globalStore.vm.addImportHandler(named: "string_len", namespace: namespace, block: self.string_len)
        try? globalStore.vm.addImportHandler(named: "read_string", namespace: namespace, block: self.read_string)
        try? globalStore.vm.addImportHandler(named: "read_int", namespace: namespace, block: self.read_int)
        try? globalStore.vm.addImportHandler(named: "read_float", namespace: namespace, block: self.read_float)
        try? globalStore.vm.addImportHandler(named: "read_bool", namespace: namespace, block: self.read_bool)
        try? globalStore.vm.addImportHandler(named: "read_date", namespace: namespace, block: self.read_date)
        try? globalStore.vm.addImportHandler(named: "read_date_string", namespace: namespace, block: self.read_date_string)

        try? globalStore.vm.addImportHandler(named: "object_len", namespace: namespace, block: self.object_len)
        try? globalStore.vm.addImportHandler(named: "object_get", namespace: namespace, block: self.object_get)
        try? globalStore.vm.addImportHandler(named: "object_set", namespace: namespace, block: self.object_set)
        try? globalStore.vm.addImportHandler(named: "object_remove", namespace: namespace, block: self.object_remove)
        try? globalStore.vm.addImportHandler(named: "object_keys", namespace: namespace, block: self.object_keys)
        try? globalStore.vm.addImportHandler(named: "object_values", namespace: namespace, block: self.object_values)

        try? globalStore.vm.addImportHandler(named: "array_len", namespace: namespace, block: self.array_len)
        try? globalStore.vm.addImportHandler(named: "array_get", namespace: namespace, block: self.array_get)
        try? globalStore.vm.addImportHandler(named: "array_set", namespace: namespace, block: self.array_set)
        try? globalStore.vm.addImportHandler(named: "array_append", namespace: namespace, block: self.array_append)
        try? globalStore.vm.addImportHandler(named: "array_remove", namespace: namespace, block: self.array_remove)
    }
}

// MARK: - Memory
extension WasmStd {

    var copy: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(json) {
                return self.globalStore.storeStdValue(object)
            }
            return -1
        }
    }

    var destroy: (Int32) -> Void {
        { json in
            self.globalStore.removeStdValue(json)
        }
    }
}

// MARK: - Create
extension WasmStd {

    var create_null: () -> Int32 {
        {
            self.globalStore.storeStdValue(nil)
        }
    }

    var create_int: (Int64) -> Int32 {
        { int in
            self.globalStore.storeStdValue(int)
        }
    }

    var create_float: (Float32) -> Int32 {
        { float in
            self.globalStore.storeStdValue(float)
        }
    }

    var create_string: (Int32, Int32) -> Int32 {
        { string, string_len in
            if let value = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(string), length: Int(string_len)) {
                return self.globalStore.storeStdValue(value)
            }
            return -1
        }
    }

    var create_bool: (Int32) -> Int32 {
        { bool in
            self.globalStore.storeStdValue(bool != 0)
        }
    }

    var create_object: () -> Int32 {
        {
            self.globalStore.storeStdValue([:])
        }
    }

    var create_array: () -> Int32 {
        {
            self.globalStore.storeStdValue([])
        }
    }

    var create_date: (Float64) -> Int32 {
        { time in
            self.globalStore.storeStdValue(Date(timeIntervalSince1970: time))
        }
    }
}

// MARK: - Read
extension WasmStd {

    var typeof: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            let value = self.globalStore.readStdValue(json)
            if value is Int {
                return Int32(ObjectType.int.rawValue)
            } else if value is Float {
                return Int32(ObjectType.float.rawValue)
            } else if value is String {
                return Int32(ObjectType.string.rawValue)
            } else if value is Bool {
                return Int32(ObjectType.bool.rawValue)
            } else if value is [Any?] {
                return Int32(ObjectType.array.rawValue)
            } else if value is [String: Any?] {
                return Int32(ObjectType.object.rawValue)
            } else if value is Date {
                return Int32(ObjectType.date.rawValue)
            }
            return -1
        }
    }

    var string_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let string = self.globalStore.readStdValue(json) as? String {
                return Int32(string.utf8.count)
            }
            return -1
        }
    }

    var read_string: (Int32, Int32, Int32) -> Void {
        { json, buffer, size in
            guard json >= 0, size >= 0 else { return }
            if let string = self.globalStore.readStdValue(json) as? String, Int(size) <= string.utf8.count {
                try? self.globalStore.vm.writeToHeap(
                    bytes: string.utf8.dropLast(string.utf8.count - Int(size)),
                    byteOffset: Int(buffer)
                )
            }
        }
    }

    var read_int: (Int32) -> Int64 {
        { json in
            guard json >= 0 else { return 0 }
            if let int = self.globalStore.readStdValue(json) as? Int {
                return Int64(int)
            } else if let int = Int(self.globalStore.readStdValue(json) as? String ?? "Error") {
                return Int64(int)
            }
            return 0
        }
    }

    var read_float: (Int32) -> Float64 {
        { json in
            guard json >= 0 else { return 0 }
            if let float = self.globalStore.readStdValue(json) as? Float {
                return Float64(float)
            } else if let float = Float(self.globalStore.readStdValue(json) as? String ?? "Error") {
                return Float64(float)
            }
            return 0
        }
    }

    var read_bool: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            if let bool = self.globalStore.readStdValue(json) as? Bool {
                return Int32(bool ? 1 : 0)
            } else if let int = self.globalStore.readStdValue(json) as? Int {
                return Int32(int != 0 ? 1 : 0)
            }
            return 0
        }
    }

    var read_date: (Int32) -> Float64 {
        { json in
            if json >= 0, let date = self.globalStore.readStdValue(json) as? Date {
                return Float64(date.timeIntervalSince1970)
            } else {
                return -1
            }
        }
    }

    var read_date_string: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Float64 {
        { json, format, format_len, locale, locale_len, timeZone, timeZone_len in
            guard json >= 0, format_len > 0 else { return -1 }
            if let string = self.globalStore.readStdValue(json) as? String,
               let formatString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(format), length: Int(format_len)) {
                let localeString = locale_len > 0 ? (try? self.globalStore.vm.stringFromHeap(
                    byteOffset: Int(locale),
                    length: Int(locale_len))
                ) : nil
                let timeZoneString = timeZone_len > 0 ? (try? self.globalStore.vm.stringFromHeap(
                    byteOffset: Int(timeZone),
                    length: Int(timeZone_len))
                ) : nil

                let formatter = DateFormatter()
                if let localeString = localeString {
                    formatter.locale = Locale(identifier: localeString)
                }
                if let timeZoneString = timeZoneString {
                    formatter.timeZone = TimeZone(identifier: timeZoneString)
                }
                formatter.dateFormat = formatString
                if let date = formatter.date(from: string) {
                    return Float64(date.timeIntervalSince1970)
                }
            }
            return -1
        }
    }
}

// MARK: - Object
extension WasmStd {

    var object_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            return Int32((self.globalStore.readStdValue(json) as? [String: Any?])?.count ?? 0)
        }
    }

    var object_get: (Int32, Int32, Int32) -> Int32 {
        { json, key, keyLength in
            guard json >= 0, keyLength > 0 else { return -1 }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(keyLength)) {
                if let object = (self.globalStore.readStdValue(json) as? [String: Any?])?[keyString] {
                    return self.globalStore.storeStdValue(object, from: json)
                } else if let object = self.globalStore.readStdValue(json) as? KVCObject,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: json)
                }
            }
            return -1
        }
    }

    var object_set: (Int32, Int32, Int32, Int32) -> Void {
        { json, key, key_len, value in
            guard json >= 0, key >= 0, value >= 0 else { return }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.globalStore.readStdValue(json) as? [String: Any?],
               let valueToSet = self.globalStore.readStdValue(value) {
                object[keyString] = valueToSet
                self.globalStore.stdDescriptors[json] = object
                self.globalStore.addStdReference(to: json, target: value)
            }
        }
    }

    var object_remove: (Int32, Int32, Int32) -> Void {
        { json, key, key_len in
            guard json >= 0, key >= 0 else { return }
            if let keyString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(key), length: Int(key_len)),
               var object = self.globalStore.readStdValue(json) as? [String: Any?] {
                object.removeValue(forKey: keyString)
                self.globalStore.stdDescriptors[json] = object
            }
        }
    }

    var object_keys: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(json) as? [String: Any?] {
                return self.globalStore.storeStdValue(Array(object.keys), from: json)
            }
            return -1
        }
    }

    var object_values: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(json) as? [String: Any] {
                return self.globalStore.storeStdValue(Array(object.values), from: json)
            }
            return -1
        }
    }
}

// MARK: - Array
extension WasmStd {

    var array_len: (Int32) -> Int32 {
        { json in
            guard json >= 0 else { return 0 }
            return Int32((self.globalStore.readStdValue(json) as? [Any?])?.count ?? 0)
        }
    }

    var array_get: (Int32, Int32) -> Int32 {
        { json, index in
            guard json >= 0, index >= 0 else { return -1 }
            if let array = self.globalStore.readStdValue(json) as? [Any?] {
                guard index < array.count else { return -1 }
                let value = array[Int(index)]
                return self.globalStore.storeStdValue(value, from: json)
            }
            return -1
        }
    }

    var array_set: (Int32, Int32, Int32) -> Void {
        { json, index, value in
            guard json >= 0, value >= 0, index >= 0 else { return }
            if var array = self.globalStore.readStdValue(json) as? [Any?],
               let valueToSet = self.globalStore.readStdValue(value),
               index < array.count {
                array[Int(index)] = valueToSet
                self.globalStore.stdDescriptors[json] = array
                self.globalStore.addStdReference(to: json, target: value)
            }
        }
    }

    var array_append: (Int32, Int32) -> Void {
        { json, value in
            guard json >= 0, value >= 0 else { return }
            if var array = self.globalStore.readStdValue(json) as? [Any?],
               let valueToAppend = self.globalStore.readStdValue(value) {
                array.append(valueToAppend)
                self.globalStore.stdDescriptors[json] = array
                self.globalStore.addStdReference(to: json, target: value)
            }
        }
    }

    var array_remove: (Int32, Int32) -> Void {
        { json, index in
            guard json >= 0, index >= 0 else { return }
            if var array = self.globalStore.readStdValue(json) as? [Any?] {
                guard index < array.count else { return }
                array.remove(at: Int(index))
                self.globalStore.stdDescriptors[json] = array
            }
        }
    }
}

// TODO: move this
// extension WasmJson {
// }