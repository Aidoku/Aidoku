//
//  SettingItem.swift
//  Aidoku
//
//  Created by Skitty on 2/17/22.
//

import Foundation

// types: group, select, multi-select, switch, stepper, segment, text, page, button, link
// TODO: slider
struct SettingItem: Codable {
    var type: String

    var key: String?
    var action: String?
    var title: String?
    var subtitle: String?
    var footer: String?
    var placeholder: String?
    var values: [String]?
    var titles: [String]?
    var defaultValue: JsonAnyValue?
    var notification: String?

    var requires: String?
    var requiresFalse: String?

    var authToEnable: Bool?
    var authToDisable: Bool?
    var authToOpen: Bool?

    // stepper
    var minimumValue: Double?
    var maximumValue: Double?

    var destructive: Bool? // button
    var external: Bool? // link

    var items: [SettingItem]? // group, page

    // text
    var autocapitalizationType: Int?
    var autocorrectionType: Int?
    var spellCheckingType: Int?
    var keyboardType: Int?
    var returnKeyType: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case key
        case action
        case title
        case subtitle
        case footer
        case placeholder
        case values
        case titles
        case defaultValue = "default"
        case notification

        case requires
        case requiresFalse
        case authToEnable
        case authToDisable
        case minimumValue
        case maximumValue
        case destructive
        case external
        case items

        case autocapitalizationType
        case autocorrectionType
        case spellCheckingType
        case keyboardType
        case returnKeyType
    }
}

enum JsonAnyType: Int {
    case null = 0
    case int = 1
    case string = 3
    case bool = 4
    case array = 5
    case object = 6
}

struct JsonAnyValue: Codable {
    let type: JsonAnyType

    let boolValue: Bool
    let intValue: Int?
    let stringValue: String?
    let stringArrayValue: [String]?
    let objectValue: [String: JsonAnyValue]?

    init(
        type: JsonAnyType,
        boolValue: Bool,
        intValue: Int? = nil,
        stringValue: String? = nil,
        stringArrayValue: [String]? = nil,
        objectValue: [String: JsonAnyValue]? = nil
    ) {
        self.type = type
        self.boolValue = boolValue
        self.intValue = intValue
        self.stringValue = stringValue
        self.stringArrayValue = stringArrayValue
        self.objectValue = objectValue
    }

    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            type = .bool
            boolValue = bool
            intValue = bool ? 1 : 0
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let int = try? container.decode(Int.self) {
            type = .int
            boolValue = int > 0
            intValue = int
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let string = try? container.decode(String.self) {
            type = .string
            boolValue = false
            intValue = nil
            stringValue = string
            stringArrayValue = nil
            objectValue = nil
        } else if let strings = try? container.decode([String].self) {
            type = .array
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = strings
            objectValue = nil
        } else if let object = try? container.decode([String: JsonAnyValue].self) {
            type = .object
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = object
        } else {
            type = .null
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try boolValue ? container.encode(boolValue) : container.encode(false)
    }

    func toRaw() -> Any? {
        switch type {
        case .null: return nil
        case .int: return intValue
        case .string: return stringValue
        case .bool: return boolValue
        case .array: return stringArrayValue
        case .object: return objectValue
        }
    }
}
