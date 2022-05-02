//
//  WasmJson.swift
//  Aidoku
//
//  Created by Skitty on 1/6/22.
//

import Foundation
import WasmInterpreter

class WasmJson {

    var globalStore: WasmGlobalStore

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "json") {
        try? globalStore.vm.addImportHandler(named: "parse", namespace: namespace, block: self.parse)
    }

    var parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard size > 0 else { return -1 }

            if let data = self.globalStore.readData(offset: data, length: size),
               let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
               json is [String: Any?] || json is [Any?] {
                return self.globalStore.storeStdValue(json)
            }

            return -1
        }
    }
}
