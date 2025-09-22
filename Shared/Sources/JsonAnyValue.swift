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
    case intArray = 8
}

struct JsonAnyValue: Hashable {
    let type: JsonAnyType

    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var intArrayValue: [Int]?
    var stringArrayValue: [String]?
    var objectValue: [String: JsonAnyValue]?

    func toRaw() -> Any? {
        switch type {
        case .null: return nil
        case .int: return intValue
        case .string: return stringValue
        case .bool: return boolValue
        case .array: return stringArrayValue
        case .object: return objectValue?.mapValues { $0.toRaw() }
        case .double: return doubleValue
        case .intArray: return intArrayValue
        }
    }
}

extension JsonAnyValue: Codable {
    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            type = .bool
            boolValue = bool
            intValue = nil
            doubleValue = nil
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let int = try? container.decode(Int.self) {
            type = .int
            boolValue = nil
            intValue = int
            doubleValue = Double(int)
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let float = try? container.decode(Float.self) {
            type = .double
            boolValue = nil
            intValue = Int(float)
            doubleValue = Double(float)
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let double = try? container.decode(Double.self) {
            type = .double
            boolValue = nil
            intValue = Int(double)
            doubleValue = double
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let string = try? container.decode(String.self) {
            type = .string
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = string
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = nil
        } else if let ints = try? container.decode([Int].self) {
            type = .array
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            intArrayValue = ints
            stringArrayValue = nil
            objectValue = nil
        } else if let strings = try? container.decode([String].self) {
            type = .array
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = strings
            objectValue = nil
        } else if let object = try? container.decode([String: JsonAnyValue].self) {
            type = .object
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            intArrayValue = nil
            stringArrayValue = nil
            objectValue = object
        } else {
            type = .null
            boolValue = nil
            intValue = nil
            doubleValue = nil
            stringValue = nil
            intArrayValue = nil
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
        case .intArray: try container.encode(intArrayValue)
        }
    }
}

extension JsonAnyValue {
    static func null() -> JsonAnyValue {
        .init(type: .null)
    }

    static func string(_ value: String) -> JsonAnyValue {
        .init(type: .string, stringValue: value)
    }

    static func int(_ value: Int) -> JsonAnyValue {
        .init(type: .int, intValue: value, doubleValue: Double(value))
    }

    static func double(_ value: Double) -> JsonAnyValue {
        .init(type: .double, intValue: Int(value), doubleValue: value)
    }

    static func bool(_ value: Bool) -> JsonAnyValue {
        .init(type: .bool, boolValue: value)
    }

    static func array(_ value: [String]) -> JsonAnyValue {
        .init(type: .array, stringArrayValue: value)
    }

    static func intArray(_ value: [Int]) -> JsonAnyValue {
        .init(type: .intArray, intArrayValue: value)
    }

    static func object(_ value: [String: JsonAnyValue]) -> JsonAnyValue {
        .init(type: .object, objectValue: value)
    }
}
