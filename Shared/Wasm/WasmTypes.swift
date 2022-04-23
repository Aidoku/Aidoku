//
//  WasmTypes.swift
//  Aidoku
//
//  Created by Skitty on 4/22/22.
//

import Foundation

public protocol WasmTypeProtocol {
    func toString() -> String
}

extension Int32: WasmTypeProtocol {
    public func toString() -> String {
        String(self)
    }
}
extension Int64: WasmTypeProtocol {
    public func toString() -> String {
        String(self)
    }
}
extension Float32: WasmTypeProtocol {
    public func toString() -> String {
        String(self)
    }
}
extension Float64: WasmTypeProtocol {
    public func toString() -> String {
        String(self)
    }
}

typealias WasmWrapperReturningFunction = ([WasmTypeProtocol]) -> WasmTypeProtocol
typealias WasmWrapperVoidFunction = ([WasmTypeProtocol]) -> Void
