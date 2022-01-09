//
//  WasmExtensions.swift
//  Aidoku
//
//  Created by Skitty on 1/7/22.
//

import Foundation
import WebAssembly

extension Interpreter {
    func write(string: String) -> Int32 {
        self.write(data: string.int32Array)
    }
    
    func write(data: [Int32]) -> Int32 {
        let offset = WasmManager.shared.memory.malloc(Int32(4 * data.count))
        try? self.writeToHeap(values: data, byteOffset: Int(offset))
        return offset
    }
    
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

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
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
        return toByteArr(endian: self.littleEndian, count: MemoryLayout<UInt32>.size)
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
