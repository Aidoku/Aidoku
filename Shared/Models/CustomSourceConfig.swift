//
//  CustomSourceConfig.swift
//  Aidoku
//
//  Created by Skitty on 5/25/25.
//

import AidokuRunner
import Foundation

enum CustomSourceConfig {
    case demo
    case local
    case komga(key: String, name: String, server: String)
}

extension CustomSourceConfig {
    func toSource() -> AidokuRunner.Source {
        switch self {
            case .demo:
                .demo()
            case .local:
                .local()
            case .komga(let key, let name, let server):
                .komga(key: key, name: name, server: server)
        }
    }
}

// MARK: Coding
extension CustomSourceConfig {
    init(from data: Data) throws {
        guard data.count >= 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Invalid byte count"
            ))
        }

        var currentIndex = 1

        func decodeString() throws -> String {
            let length: UInt64 = try decodeVarInt(data, currentIndex: &currentIndex)
            let endIndex = currentIndex.advanced(by: Int(truncatingIfNeeded: length))
            guard endIndex <= data.endIndex && endIndex >= currentIndex else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid string length")
                )
            }
            let stringData = data[currentIndex..<endIndex]
            currentIndex = endIndex
            return String(data: stringData, encoding: .utf8) ?? ""
        }

        switch data[0] {
            case 0:
                self = .demo
            case 1:
                let key = try decodeString()
                let name = try decodeString()
                let server = try decodeString()
                self = .komga(key: key, name: name, server: server)
            case 2:
                self = .local
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Invalid type"
                ))
        }
    }

    func encode() -> Data {
        var bytes = Data()

        switch self {
            case .demo:
                bytes.append(0)
            case .komga(let key, let name, let server):
                bytes.append(1)
                for string in [key, name, server] {
                    let utf8 = [UInt8](string.utf8)
                    varInt(UInt64(utf8.count), data: &bytes)
                    bytes.append(contentsOf: utf8)
                }
            case .local:
                bytes.append(2)
        }

        return bytes
    }
}
