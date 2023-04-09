//
//  WasmStd.swift
//  Aidoku
//
//  Created by Skitty on 3/31/22.
//

import Foundation
import SwiftSoup

class WasmStd: WasmImports {

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
        case node = 8
        case unknown = 9
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
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(descriptor) {
                return self.globalStore.storeStdValue(object)
            }
            return -1
        }
    }

    var destroy: (Int32) -> Void {
        { descriptor in
            self.globalStore.removeStdValue(descriptor)
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
            self.globalStore.storeStdValue(Int(int))
        }
    }

    var create_float: (Float64) -> Int32 {
        { float in
            self.globalStore.storeStdValue(Float(float))
        }
    }

    var create_string: (Int32, Int32) -> Int32 {
        { string, stringLen in
            if let value = self.globalStore.readString(offset: string, length: stringLen) {
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
            self.globalStore.storeStdValue([AnyHashable: AnyHashable]())
        }
    }

    var create_array: () -> Int32 {
        {
            self.globalStore.storeStdValue([AnyHashable]())
        }
    }

    var create_date: (Float64) -> Int32 {
        { time in
            self.globalStore.storeStdValue(time < 0 ? Date() : Date(timeIntervalSince1970: time))
        }
    }
}

// MARK: - Read
extension WasmStd {

    var typeof: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return Int32(ObjectType.null.rawValue) }
            let value = self.globalStore.readStdValue(descriptor)
            if value == nil || value is NSNull {
                return Int32(ObjectType.null.rawValue)
            } else if value is Int {
                return Int32(ObjectType.int.rawValue)
            } else if value is Float {
                return Int32(ObjectType.float.rawValue)
            } else if let value = value as? NSNumber {
                switch CFNumberGetType(value) {
                case .floatType, .float32Type, .float64Type, .cgFloatType:
                    return Int32(ObjectType.float.rawValue)
                default:
                    return Int32(ObjectType.int.rawValue)
                }
            } else if value is String {
                return Int32(ObjectType.string.rawValue)
            } else if value is Bool {
                return Int32(ObjectType.bool.rawValue)
            } else if value is [Any?] {
                return Int32(ObjectType.array.rawValue)
            } else if value is [String: Any?] || value is KVCObject
                        || value is Manga || value is Chapter || value is FilterBase || value is Listing
                        || value is WasmRequestObject || value is WasmResponseObject {
                return Int32(ObjectType.object.rawValue)
            } else if value is Date {
                return Int32(ObjectType.date.rawValue)
            } else if value is SwiftSoup.Element || value is SwiftSoup.Elements {
                return Int32(ObjectType.node.rawValue)
            }
            return Int32(ObjectType.unknown.rawValue)
        }
    }

    var string_len: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = self.globalStore.readStdValue(descriptor) as? String {
                return Int32(string.utf8.count)
            }
            return -1
        }
    }

    var read_string: (Int32, Int32, Int32) -> Void {
        { descriptor, buffer, size in
            guard descriptor >= 0, size >= 0 else { return }
            if let string = self.globalStore.readStdValue(descriptor) as? String, Int(size) <= string.utf8.count {
                self.globalStore.write(bytes: string.utf8.dropLast(string.utf8.count - Int(size)), offset: buffer)
            }
        }
    }

    var read_int: (Int32) -> Int64 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            let value = self.globalStore.readStdValue(descriptor)
            if let int = value as? Int {
                return Int64(int)
            } else if let float = value as? Float {
                return Int64(float)
            } else if let int = Int(value as? String ?? "Error") {
                return Int64(int)
            } else if let bool = value as? Bool {
                return Int64(bool ? 1 : 0)
            } else if let number = value as? NSNumber {
                return number.int64Value
            }
            return -1
        }
    }

    var read_float: (Int32) -> Float64 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            let value = self.globalStore.readStdValue(descriptor)
            if let float = value as? Float {
                return Float64(float)
            } else if let int = value as? Int {
                return Float64(int)
            } else if let float = Float(value as? String ?? "Error") {
                return Float64(float)
            } else if let number = value as? NSNumber {
                return number.doubleValue
            }
            return -1
        }
    }

    var read_bool: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            if let bool = self.globalStore.readStdValue(descriptor) as? Bool {
                return Int32(bool ? 1 : 0)
            } else if let int = self.globalStore.readStdValue(descriptor) as? Int {
                return Int32(int != 0 ? 1 : 0)
            }
            return 0
        }
    }

    var read_date: (Int32) -> Float64 {
        { descriptor in
            if descriptor >= 0, let date = self.globalStore.readStdValue(descriptor) as? Date {
                return Float64(date.timeIntervalSince1970)
            } else {
                return -1
            }
        }
    }

    var read_date_string: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Float64 {
        { descriptor, format, formatLen, locale, localeLen, timeZone, timeZoneLen in
            guard descriptor >= 0, formatLen > 0 else { return -1 }
            if let string = self.globalStore.readStdValue(descriptor) as? String,
               let formatString = self.globalStore.readString(offset: format, length: formatLen) {
                let localeString = localeLen > 0 ? self.globalStore.readString(offset: locale, length: localeLen) : nil
                let timeZoneString = timeZoneLen > 0 ? self.globalStore.readString(offset: timeZone, length: timeZoneLen) : nil

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
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            return Int32((self.globalStore.readStdValue(descriptor) as? [String: Any?])?.count ?? 0)
        }
    }

    var object_get: (Int32, Int32, Int32) -> Int32 {
        { descriptor, key, keyLen in
            guard descriptor >= 0, keyLen > 0 else { return -1 }
            if let keyString = self.globalStore.readString(offset: key, length: keyLen) {
                if let object = (self.globalStore.readStdValue(descriptor) as? [String: Any?])?[keyString] {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                } else if let object = self.globalStore.readStdValue(descriptor) as? KVCObject,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)

                // for iOS 14
                } else if let object = self.globalStore.readStdValue(descriptor) as? Manga,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)
                } else if let object = self.globalStore.readStdValue(descriptor) as? Chapter,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)
                } else if let object = self.globalStore.readStdValue(descriptor) as? FilterBase,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)
                } else if let object = self.globalStore.readStdValue(descriptor) as? Listing,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)
                } else if let object = self.globalStore.readStdValue(descriptor) as? WasmRequestObject,
                          let value = object.valueByPropertyName(name: keyString) {
                    return self.globalStore.storeStdValue(value, from: descriptor)
                }
            }
            return -1
        }
    }

    var object_set: (Int32, Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLen, value in
            guard descriptor >= 0, keyLen >= 0, value >= 0 else { return }
            if let keyString = self.globalStore.readString(offset: key, length: keyLen),
               var object = self.globalStore.readStdValue(descriptor) as? [String: Any?],
               let valueToSet = self.globalStore.readStdValue(value) {
                object[keyString] = valueToSet
                self.globalStore.stdDescriptors[descriptor] = object
                self.globalStore.addStdReference(to: descriptor, target: value)
            }
        }
    }

    var object_remove: (Int32, Int32, Int32) -> Void {
        { descriptor, key, keyLen in
            guard descriptor >= 0, keyLen >= 0 else { return }
            if let keyString = self.globalStore.readString(offset: key, length: keyLen),
               var object = self.globalStore.readStdValue(descriptor) as? [String: Any?] {
                object.removeValue(forKey: keyString)
                self.globalStore.stdDescriptors[descriptor] = object
            }
        }
    }

    var object_keys: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(descriptor) as? [String: Any?] {
                return self.globalStore.storeStdValue(Array(object.keys), from: descriptor)
            }
            return -1
        }
    }

    var object_values: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let object = self.globalStore.readStdValue(descriptor) as? [String: Any?] {
                return self.globalStore.storeStdValue(Array(object.values), from: descriptor)
            }
            return -1
        }
    }
}

// MARK: - Array
extension WasmStd {

    var array_len: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            return Int32((self.globalStore.readStdValue(descriptor) as? [Any?])?.count ?? 0)
        }
    }

    var array_get: (Int32, Int32) -> Int32 {
        { descriptor, index in
            guard descriptor >= 0, index >= 0 else { return -1 }
            if let array = self.globalStore.readStdValue(descriptor) as? [Any?] {
                guard index < array.count else { return -1 }
                let value = array[Int(index)]
                return self.globalStore.storeStdValue(value, from: descriptor)
            }
            return -1
        }
    }

    var array_set: (Int32, Int32, Int32) -> Void {
        { descriptor, index, value in
            guard descriptor >= 0, value >= 0, index >= 0 else { return }
            if var array = self.globalStore.readStdValue(descriptor) as? [Any?],
               let valueToSet = self.globalStore.readStdValue(value),
               index < array.count {
                array[Int(index)] = valueToSet
                self.globalStore.stdDescriptors[descriptor] = array
                self.globalStore.addStdReference(to: descriptor, target: value)
            }
        }
    }

    var array_append: (Int32, Int32) -> Void {
        { descriptor, value in
            guard descriptor >= 0, value >= 0 else { return }
            if var array = self.globalStore.readStdValue(descriptor) as? [Any?],
               let valueToAppend = self.globalStore.readStdValue(value) {
                array.append(valueToAppend)
                self.globalStore.stdDescriptors[descriptor] = array
                self.globalStore.addStdReference(to: descriptor, target: value)
            }
        }
    }

    var array_remove: (Int32, Int32) -> Void {
        { descriptor, index in
            guard descriptor >= 0, index >= 0 else { return }
            if var array = self.globalStore.readStdValue(descriptor) as? [Any?] {
                guard index < array.count else { return }
                array.remove(at: Int(index))
                self.globalStore.stdDescriptors[descriptor] = array
            }
        }
    }
}
