//
//  SettingsValue.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

protocol SettingsValue {
    static func deserialize(from object: Any) -> Self?
    func serialize() -> Any?
}

extension SettingsValue {
    static func deserialize(from object: Any) -> Self? {
        guard let object = object as? Self else { return nil }
        return object
    }

    func serialize() -> Any? {
        self as Any
    }
}
