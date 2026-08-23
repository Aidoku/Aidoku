//
//  SettingsKey.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

import Foundation

protocol SettingsDefault {
    var key: String { get }
    var defaultObject: Any? { get }
}

struct SettingsKey<Value: SettingsValue>: SettingsDefault {
    let key: String
    let defaultValue: Value
    let requires: (() -> Value?)?

    var defaultObject: Any? {
        defaultValue.serialize()
    }

    init(
        _ key: String,
        default defaultValue: Value,
        requires: (() -> Value?)? = nil
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.requires = requires
    }

    func get() -> Value {
        if let requires, let result = requires() {
            return result
        }
        let object = UserDefaults.standard.object(forKey: key)
        return object.flatMap(Value.deserialize) ?? defaultValue
    }

    func set(_ value: Value) {
        let object = value.serialize()
        UserDefaults.standard.set(object, forKey: key)
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension SettingsKey where Value: ExpressibleByNilLiteral {
    init(_ key: String) {
        self.init(key, default: nil)
    }
}
