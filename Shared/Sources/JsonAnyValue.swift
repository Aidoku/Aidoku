//
//  JsonAnyValue.swift
//  Aidoku
//
//  Created by Skitty on 6/24/22.
//

import Foundation

enum JsonAnyType: Int {
    case null = 0
    case int = 1
    case string = 3
    case bool = 4
    case array = 5
    case object = 6
    case double = 7
}

struct JsonAnyValue: Codable {
    let type: JsonAnyType

    let boolValue: Bool?
    let intValue: Int?
    let doubleValue: Double?
    let stringValue: String?
    let stringArrayValue: [String]?
    let objectValue: [String: JsonAnyValue]?

    init(
        type: JsonAnyType,
        boolValue: Bool? = nil,
        intValue: Int? = nil,
        doubleValue: Double? = nil,
        stringValue: String? = nil,
        stringArrayValue: [String]? = nil,
        objectValue: [String: JsonAnyValue]? = nil
    ) {
        self.type = type
        self.boolValue = boolValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.stringValue = stringValue
        self.stringArrayValue = stringArrayValue
        self.objectValue = objectValue
    }

    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            type = .bool
            boolValue = bool
            intValue = nil
            doubleValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let int = try? container.decode(Int.self) {
            type = .int
            boolValue = nil
            intValue = int
            doubleValue = Double(int)
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let float = try? container.decode(Float.self) {
            type = .double
            boolValue = nil
            intValue = Int(float)
            doubleValue = Double(float)
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let double = try? container.decode(Double.self) {
            type = .double
            boolValue = nil
            intValue = Int(double)
            doubleValue = double
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let string = try? container.decode(String.self) {
            type = .string
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = string
            stringArrayValue = nil
            objectValue = nil
        } else if let strings = try? container.decode([String].self) {
            type = .array
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            stringArrayValue = strings
            objectValue = nil
        } else if let object = try? container.decode([String: JsonAnyValue].self) {
            type = .object
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = object
        } else {
            type = .null
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            stringArrayValue = nil
            objectValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch type {
        case .null: break
        case .int: try container.encode(intValue)
        case .string: try container.encode(stringValue)
        case .bool: try container.encode(boolValue)
        case .array: try container.encode(stringArrayValue)
        case .object: try container.encode(objectValue)
        case .double: try container.encode(doubleValue)
        }
    }

    func toRaw() -> Any? {
        switch type {
        case .null: return nil
        case .int: return intValue
        case .string: return stringValue
        case .bool: return boolValue
        case .array: return stringArrayValue
        case .object: return objectValue?.mapValues { $0.toRaw() }
        case .double: return doubleValue
        }
    }
}
