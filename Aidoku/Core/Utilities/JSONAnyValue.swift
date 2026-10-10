//
//  JSONAnyValue.swift
//  Aidoku
//
//  Created by Skitty on 6/24/22.
//

import Foundation

enum JSONAnyType: Int {
    case null = 0
    case int = 1
    case string = 3
    case bool = 4
    case array = 5
    case object = 6
    case double = 7
    case intArray = 8
    case data = 9
}

struct JSONAnyValue: Hashable, Sendable {
    let type: JSONAnyType

    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var intArrayValue: [Int]?
    var stringArrayValue: [String]?
    var objectValue: [String: JSONAnyValue]?
    var dataValue: Data?

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
            case .data: return dataValue
        }
    }
}

extension JSONAnyValue: Codable {
    private struct EncodedData: Codable {
        let aidokuData: Data
    }

    init(from decoder: Decoder) throws {
        let container =  try decoder.singleValueContainer()

        dataValue = nil
        boolValue = nil
        intValue = nil
        doubleValue = nil
        stringValue = nil
        intArrayValue = nil
        stringArrayValue = nil
        objectValue = nil

        if let data = try? container.decode(EncodedData.self) {
            type = .data
            dataValue = data.aidokuData
        } else if let bool = try? container.decode(Bool.self) {
            type = .bool
            boolValue = bool
        } else if let int = try? container.decode(Int.self) {
            type = .int
            intValue = int
            doubleValue = Double(int)
        } else if let float = try? container.decode(Float.self) {
            type = .double
            intValue = Int(float)
            doubleValue = Double(float)
        } else if let double = try? container.decode(Double.self) {
            type = .double
            intValue = Int(double)
            doubleValue = double
        } else if let string = try? container.decode(String.self) {
            type = .string
            stringValue = string
        } else if let ints = try? container.decode([Int].self) {
            type = .intArray
            intArrayValue = ints
        } else if let strings = try? container.decode([String].self) {
            type = .array
            stringArrayValue = strings
        } else if let object = try? container.decode([String: JSONAnyValue].self) {
            type = .object
            objectValue = object
        } else {
            type = .null
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
            case .data:
                guard let dataValue else {
                    throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Missing data value"))
                }
                try container.encode(EncodedData(aidokuData: dataValue))
        }
    }
}

extension JSONAnyValue {
    static func null() -> JSONAnyValue {
        .init(type: .null)
    }

    static func string(_ value: String) -> JSONAnyValue {
        .init(type: .string, stringValue: value)
    }

    static func int(_ value: Int) -> JSONAnyValue {
        .init(type: .int, intValue: value, doubleValue: Double(value))
    }

    static func double(_ value: Double) -> JSONAnyValue {
        .init(type: .double, intValue: Int(value), doubleValue: value)
    }

    static func bool(_ value: Bool) -> JSONAnyValue {
        .init(type: .bool, boolValue: value)
    }

    static func array(_ value: [String]) -> JSONAnyValue {
        .init(type: .array, stringArrayValue: value)
    }

    static func intArray(_ value: [Int]) -> JSONAnyValue {
        .init(type: .intArray, intArrayValue: value)
    }

    static func data(_ value: Data) -> JSONAnyValue {
        .init(type: .data, dataValue: value)
    }

    static func object(_ value: [String: JSONAnyValue]) -> JSONAnyValue {
        .init(type: .object, objectValue: value)
    }
}
