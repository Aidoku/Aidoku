//
//  Wasmswift
//  Aidoku
//
//  Created by Skitty on 3/30/22.
//

import Foundation

class WasmGlobalStore {

    var id: String
    var wrapper: WasmWrapper

    var chapterCounter = 0
    var currentManga = ""

    // std
    var stdDescriptorPointer: Int32 = -1
    var stdDescriptors: [Int32: Any?] = [:]
    var stdReferences: [Int32: [Int32]] = [:]

    // net
    var requestsPointer: Int32 = -1
    var requests: [Int32: WasmRequestObject] = [:]

    init(id: String, wrapper: WasmWrapper) {
        self.id = id
        self.wrapper = wrapper
    }

    func readStdValue(_ descriptor: Int32) -> Any? {
        stdDescriptors[descriptor] as Any?
    }

    func storeStdValue(_ data: Any?, from: Int32? = nil) -> Int32 {
        stdDescriptorPointer += 1
        stdDescriptors[stdDescriptorPointer] = data
        if let d = from {
            var refs = stdReferences[d] ?? []
            refs.append(stdDescriptorPointer)
            stdReferences[d] = refs
        }
        return stdDescriptorPointer
    }

    func removeStdValue(_ descriptor: Int32) {
        stdDescriptors.removeValue(forKey: descriptor)
        for d in stdReferences[descriptor] ?? [] {
            removeStdValue(d)
        }
        stdReferences.removeValue(forKey: descriptor)
    }

    func addStdReference(to: Int32, target: Int32) {
        var refs = stdReferences[to] ?? []
        refs.append(target)
        stdReferences[to] = refs
    }

    func call(_ function: String, args: [WasmTypeProtocol]) -> Int32? {
        wrapper.call(function, args: args)
    }

    func export(named: String, namespace: String, block: Any) {
        wrapper.addImportHandler(named: named, namespace: namespace, block: block)
    }

    func readString(offset: Int32, length: Int32) -> String? {
        wrapper.readString(offset: offset, length: length)
    }

    func readData(offset: Int32, length: Int32) -> Data? {
        wrapper.readData(offset: offset, length: length)
    }

    func readValue(offset: Int32) -> Int32? {
        wrapper.readValue(offset: offset)
    }

    func readValues(offset: Int32, length: Int32) -> [Int32]? {
        wrapper.readValues(offset: offset, length: length)
    }

    func readBytes(offset: Int32, length: Int32) -> [UInt8]? {
        wrapper.readBytes(offset: offset, length: length)
    }

    func write(value: Int32, offset: Int32) {
        wrapper.write(value: value, offset: offset)
    }

    func write(bytes: [UInt8], offset: Int32) {
        wrapper.write(bytes: bytes, offset: offset)
    }

    func write(data: Data, offset: Int32) {
        wrapper.write(data: data, offset: offset)
    }
}
