//
//  Wasmswift
//  Aidoku
//
//  Created by Skitty on 3/30/22.
//

import Foundation
import WasmInterpreter

class WasmGlobalStore {
    var vm: WasmInterpreter

    var chapterCounter = 0
    var currentManga = ""

    // std
    var stdDescriptorPointer: Int32 = -1
    var stdDescriptors: [Int32: Any?] = [:]
    var stdReferences: [Int32: [Int32]] = [:]

    // net
    var requests: [WasmRequestObject] = []

    init(vm: WasmInterpreter) {
        self.vm = vm
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
}
