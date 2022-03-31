//
//  WasmExtensions.swift
//  Aidoku
//
//  Created by Skitty on 1/7/22.
//

import Foundation
import WasmInterpreter
import CWasm3

// MARK: - WasmInterpreter
extension WasmInterpreter {

    func stringFromHeap(byteOffset: Int) -> String {
        var bytes = [UInt8]()
        var offset = byteOffset
        var doneReading = false
        while !doneReading {
            let byte = (try? self.bytesFromHeap(byteOffset: offset, length: 1).first) ?? 0
            if byte == 0 {
                doneReading = true
            } else {
                bytes.append(byte)
                offset += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}

// MARK: - UInts
public extension UnsignedInteger {
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)
        var value: UInt64 = 0
        for byte in bytes {
            value <<= 8
            value |= UInt64(byte)
        }
        self.init(value)
    }
}

protocol UIntToBytesConvertable {
    var toBytes: [UInt8] { get }
}

extension UIntToBytesConvertable {
    func toByteArr<T: BinaryInteger>(endian: T, count: Int) -> [UInt8] {
        var _endian = endian
        let bytePtr = withUnsafePointer(to: &_endian) {
            $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return [UInt8](bytePtr)
    }
}

extension UInt32: UIntToBytesConvertable {
    var toBytes: [UInt8] {
        toByteArr(endian: self.littleEndian, count: MemoryLayout<UInt32>.size)
    }
}

// MARK: - C strings
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension String {

    var nullTerminated: [UInt8] {
        var data = [UInt8](self.utf8)
        data.append(0)
        return data
    }

    var int32Array: [Int32] {
        self.nullTerminated.chunked(into: 4).map { Int32(truncatingIfNeeded: UInt32($0.reversed())) }
    }
}
