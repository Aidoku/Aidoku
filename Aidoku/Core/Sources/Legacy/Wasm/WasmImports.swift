//
//  WasmImports.swift
//  Aidoku
//
//  Created by Skitty on 3/29/22.
//

import Foundation

protocol WasmImports {
    var globalStore: WasmGlobalStore { get set }

    func export(into namespace: String)
}
