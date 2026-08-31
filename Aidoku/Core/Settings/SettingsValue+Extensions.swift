//
//  SettingsValue+Extensions.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

import Foundation

extension Bool: SettingsValue {}
extension String: SettingsValue {}
extension Int: SettingsValue {}
extension Double: SettingsValue {}
extension Data: SettingsValue {}

extension Optional: SettingsValue where Wrapped: SettingsValue {
    static func deserialize(from object: Any) -> Self? {
        Wrapped.deserialize(from: object)
    }

    func serialize() -> Any? {
        switch self {
            case .some(let value): value.serialize()
            case .none: nil
        }
    }
}

extension RawRepresentable where Self: SettingsValue, RawValue: SettingsValue {
    static func deserialize(from object: Any) -> Self? {
        guard let rawValue = RawValue.deserialize(from: object) else { return nil }
        return self.init(rawValue: rawValue)
    }

    func serialize() -> Any? {
        rawValue.serialize()
    }
}

extension Date: SettingsValue {
    static func deserialize(from object: Any) -> Self? {
        guard let interval = object as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func serialize() -> Any? {
        timeIntervalSince1970
    }
}

extension Array: SettingsValue where Element: StringConvertible {
    static func deserialize(from object: Any) -> Self? {
        guard let values = object as? [String] else {
            return nil
        }
        return values.compactMap { Element(string: $0) }
    }

    func serialize() -> Any? {
        map { $0.toString() }
    }
}

extension Set: SettingsValue where Element: StringConvertible {
    static func deserialize(from object: Any) -> Self? {
        guard let values = object as? [String] else {
            return nil
        }
        return Set(values.compactMap { Element(string: $0) })
    }

    func serialize() -> Any? {
        map { $0.toString() }.sorted()
    }
}
