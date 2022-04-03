//
//  SourceSettings.swift
//  Aidoku
//
//  Created by Skitty on 2/17/22.
//

import Foundation

// possible types: group, select, multi-select, switch, segment, text, page, button, link
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
    var defaultValue: DefaultValue?
    var notification: String?

    var requires: String?
    var requiresFalse: String?

    var destructive: Bool? // button
    var external: Bool? // link

    var items: [SettingItem]? // group, page

    enum CodingKeys: String, CodingKey {
        case type
        case items
        case key
        case action
        case title
        case subtitle
        case footer
        case placeholder
        case values
        case titles
        case defaultValue = "default"
    }
}

struct DefaultValue: Codable {
    let boolValue: Bool
    let intValue: Int?
    let stringValue: String?
    let stringArrayValue: [String]?
    let objectValue: [String: DefaultValue]?

    init(
        boolValue: Bool,
        intValue: Int? = nil,
        stringValue: String? = nil,
        stringArrayValue: [String]? = nil,
        objectValue: [String: DefaultValue]? = nil
    ) {
        self.boolValue = boolValue
        self.intValue = intValue
        self.stringValue = stringValue
        self.stringArrayValue = stringArrayValue
        self.objectValue = objectValue
    }

    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            boolValue = bool
            intValue = bool ? 1 : 0
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let int = try? container.decode(Int.self) {
            boolValue = int > 0
            intValue = int
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let string = try? container.decode(String.self) {
            boolValue = false
            intValue = nil
            stringValue = string
            stringArrayValue = nil
            objectValue = nil
        } else if let strings = try? container.decode([String].self) {
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = strings
            objectValue = nil
        } else if let object = try? container.decode([String: DefaultValue].self) {
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = object
        } else {
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
}
