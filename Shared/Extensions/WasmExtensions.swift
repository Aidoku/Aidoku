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
    
    func write(string: String, memory: WasmMemory) -> Int32 {
        self.write(data: string.int32Array, memory: memory)
    }
    
    func write(data: [Int32], memory: WasmMemory) -> Int32 {
        let offset = memory.malloc(Int32(4 * data.count))
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

public extension WasmInterpreter {
    func globalValue(name: String) throws -> Int32 {
        let global = try global(name: name)
        let taggedValue = IM3TaggedValue.allocate(capacity: MemoryLayout<M3TaggedValue>.stride)
        defer { taggedValue.deallocate() }
        try Self.check(m3_GetGlobal(global, taggedValue))
        return Int32(taggedValue.pointee.value.i32)
    }
}

private extension WasmInterpreter {
    func global(name: String) throws -> IM3Global {
        guard let global: IM3Global = m3_FindGlobal(module, name) else {
            throw WasmInterpreterError.wasm3Error(name)
        }
        return global
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
        return toByteArr(endian: self.littleEndian, count: MemoryLayout<UInt32>.size)
    }
}

// MARK: - C strings
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
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
