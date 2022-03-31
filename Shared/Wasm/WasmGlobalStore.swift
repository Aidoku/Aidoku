//
//  WasmGlobalStore.swift
//  Aidoku
//
//  Created by Skitty on 3/30/22.
//

import Foundation
import WasmInterpreter

class WasmGlobalStore {
    var vm: WasmInterpreter

    // aidoku
    var swiftDescriptorPointer = -1
    var swiftDescriptors: [Any] = []

    // net
    var requests: [WasmRequestObject] = []

    // json
    var jsonDescriptorPointer: Int32 = -1
    var jsonDescriptors: [Int32: Any?] = [:]
    var jsonReferences: [Int32: [Int32]] = [:]

    init(vm: WasmInterpreter) {
        self.vm = vm
    }
}
