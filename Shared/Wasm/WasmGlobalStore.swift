//
//  Wasmswift
//  Aidoku
//
//  Created by Skitty on 3/30/22.
//

import Foundation
import WasmInterpreter

class WasmGlobalStore {
    var id: String
    var vm: WasmInterpreter

    var chapterCounter = 0
    var currentManga = ""

    // std
    var stdDescriptorPointer: Int32 = -1
    var stdDescriptors: [Int32: Any?] = [:]
//    var stdReferences: [Int32: [Int32]] = [:]

    // net
    var requestsPointer: Int32 = -1
    var requests: [Int32: WasmRequestObject] = [:]

    init(id: String, vm: WasmInterpreter) {
        self.id = id
        self.vm = vm
    }

    func readStdValue(_ descriptor: Int32) -> Any? {
        stdDescriptors[descriptor] as Any?
    }

    func storeStdValue(_ data: Any?, from: Int32? = nil) -> Int32 {
        stdDescriptorPointer += 1
        stdDescriptors[stdDescriptorPointer] = data
//        if let d = from {
//            var refs = stdReferences[d] ?? []
//            refs.append(stdDescriptorPointer)
//            stdReferences[d] = refs
//        }
        return stdDescriptorPointer
    }

    func removeStdValue(_ descriptor: Int32) {
        stdDescriptors.removeValue(forKey: descriptor)
//        for d in stdReferences[descriptor] ?? [] {
//            removeStdValue(d)
//        }
//        stdReferences.removeValue(forKey: descriptor)
    }

    func addStdReference(to: Int32, target: Int32) {
//        var refs = stdReferences[to] ?? []
//        refs.append(target)
//        stdReferences[to] = refs
    }
}

// MARK: - Memory R/W
extension WasmGlobalStore {

    func readString(offset: Int, length: Int) -> String? {
        try? vm.stringFromHeap(byteOffset: offset, length: length)
    }

    func readString(offset: Int32, length: Int32) -> String? {
        try? vm.stringFromHeap(byteOffset: Int(offset), length: Int(length))
    }

    func readData(offset: Int32, length: Int32) -> Data? {
        try? vm.dataFromHeap(byteOffset: Int(offset), length: Int(length))
    }

    func readValue<T: WasmTypeProtocol>(offset: Int32, length: Int32) -> T? {
        try? vm.valueFromHeap(byteOffset: Int(offset))
    }

    func readValues<T: WasmTypeProtocol>(offset: Int32, length: Int32) -> [T]? {
        try? vm.valuesFromHeap(byteOffset: Int(offset), length: Int(length))
    }

    func readBytes(offset: Int32, length: Int32) -> [UInt8]? {
        try? vm.bytesFromHeap(byteOffset: Int(offset), length: Int(length))
    }

    func write<T: WasmTypeProtocol>(value: T, offset: Int32) {
        try? vm.writeToHeap(value: value, byteOffset: Int(offset))
    }

    func write(bytes: [UInt8], offset: Int32) {
        try? vm.writeToHeap(bytes: bytes, byteOffset: Int(offset))
    }

    func write(data: Data, offset: Int32) {
        try? vm.writeToHeap(data: data, byteOffset: Int(offset))
    }
}
