//
//  SettingsValue+Extensions.swift
//  Aidoku
//
//  Created by skitty on 7/16/26.
//

extension Bool: SettingsValue {}
extension String: SettingsValue {}
extension Int: SettingsValue {}
extension Double: SettingsValue {}
extension Array<String>: SettingsValue {}

extension Optional: SettingsValue where Wrapped: SettingsValue {}

extension RawRepresentable where Self: SettingsValue, RawValue: SettingsValue {
    static func deserialize(from object: Any) -> Self? {
        guard let rawValue = RawValue.deserialize(from: object) else { return nil }
        return self.init(rawValue: rawValue)
    }

    func serialize() -> Any? {
        rawValue.serialize()
    }
}
