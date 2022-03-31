//
//  WasmGlobalStore.swift
//  Aidoku
//
//  Created by Skitty on 3/30/22.
//

import Foundation
import WasmInterpreter

struct WasmGlobalStore {
    var vm: WasmInterpreter

    // net
    var requests: [WasmRequestObject] = []

    // json
    var jsonDescriptorPointer: Int32 = -1
    var jsonDescriptors: [Int32: Any?] = [:]
    var jsonReferences: [Int32: [Int32]] = [:]
}
