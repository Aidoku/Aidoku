//
//  SourceSettings.swift
//  Aidoku
//
//  Created by Skitty on 2/17/22.
//

import Foundation

struct SourceSettings: Codable {
    let languages: [String]?
    let settings: [SourceSettingItem]?
}

// possible types: group, select, multi-select, switch, text
// TODO: slider, segment
struct SourceSettingItem: Codable {
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

    var items: [SourceSettingItem]?

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

    init(boolValue: Bool, intValue: Int? = nil, stringValue: String? = nil, stringArrayValue: [String]? = nil) {
        self.boolValue = boolValue
        self.intValue = intValue
        self.stringValue = stringValue
        self.stringArrayValue = stringArrayValue
    }

    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            boolValue = bool
            intValue = bool ? 1 : 0
            stringValue = nil
            stringArrayValue = nil
        } else if let int = try? container.decode(Int.self) {
            boolValue = int > 0
            intValue = int
            stringValue = nil
            stringArrayValue = nil
        } else if let string = try? container.decode(String.self) {
            boolValue = false
            intValue = nil
            stringValue = string
            stringArrayValue = nil
        } else if let strings = try? container.decode([String].self) {
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = strings
        } else {
            boolValue = false
            intValue = nil
            stringValue = nil
            stringArrayValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try boolValue ? container.encode(boolValue) : container.encode(false)
    }
}
