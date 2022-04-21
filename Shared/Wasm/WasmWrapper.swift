//
//  WasmWrapper.swift
//  Aidoku
//
//  Created by Skitty on 4/21/22.
//

import Foundation
import JavaScriptCore

protocol WasmTypeProtocol {
    func toString() -> String
}

extension Int32: WasmTypeProtocol {
    func toString() -> String {
        String(self)
    }
}
extension Int64: WasmTypeProtocol {
    func toString() -> String {
        String(self)
    }
}
extension Float32: WasmTypeProtocol {
    func toString() -> String {
        String(self)
    }
}
extension Float64: WasmTypeProtocol {
    func toString() -> String {
        String(self)
    }
}

extension NSNumber {
    var type: CFNumberType {
        CFNumberGetType(self as CFNumber)
    }
}

class WasmWrapper {

    var module: [UInt8]
    let context = JSContext()
    var importCache: [String: [String: String]] = [:]
    var instanciated = false

    init(module: [UInt8]) {
        self.module = module

        context?.exceptionHandler = { _, error in
            if let error = error {
                let message = String(describing: error)
                print(message)
            }
        }

        let byteArray = module.map { String($0) }.joined(separator: ",")

        context?.evaluateScript("let mod=new WebAssembly.Module(new Uint8Array([\(byteArray)]))")
    }

    func createInstance() {
        var importSrc = "let imports={"
        importSrc += importCache.map {
            "\($0.key):{\(($0.value).map { "\($0.key):\($0.value)" }.joined(separator: ","))}"
        }.joined(separator: ",")
        importSrc += "};"
        context?.evaluateScript(importSrc)
        context?.evaluateScript("let inst=new WebAssembly.Instance(mod, imports);")
        instanciated = true
    }

    func addImportHandler(named: String, namespace: String, block: Any) {
        let importName = "__wasm_\(namespace)_\(named)"
        context?.setObject(block, forKeyedSubscript: importName as NSString)

        var moduleImports = importCache[namespace] ?? [:]
        moduleImports[named] = importName
        importCache[namespace] = moduleImports
    }
}

extension WasmWrapper {
    func call(_ function: String, args: [WasmTypeProtocol] = []) -> Int32? {
        if !instanciated { createInstance() }
        return context?.evaluateScript("inst.exports.\(function)(\(args.map { $0.toString() }.joined(separator: ",")))")?.toInt32()
    }

    func readBytes(offset: Int32, length: Int32) -> [UInt8]? {
        let src = "new Uint8Array(inst.exports.memory.buffer, \(offset), \(length))"
        return context?.evaluateScript(src)?.toArray() as? [UInt8]
    }

    func readValues(offset: Int32, length: Int32) -> [Int32]? {
        let src = "new Int32Array(inst.exports.memory.buffer, \(offset), \(length))"
        return context?.evaluateScript(src)?.toArray() as? [Int32]
    }

    func readValue(offset: Int32) -> Int32? {
        let src = "new Int32Array(inst.exports.memory.buffer, \(offset), 1)[0]"
        return context?.evaluateScript(src)?.toInt32()
    }

    func readString(offset: Int32, length: Int32) -> String? {
        let src = "String.fromCharCode.apply(null,new Uint8Array(inst.exports.memory.buffer,\(offset),\(length)))"
        return context?.evaluateScript(src)?.toString()
    }

    func readData(offset: Int32, length: Int32) -> Data? {
        if let bytes = readBytes(offset: offset, length: length) {
            return Data(bytes)
        }
        return nil
    }

    func write(value: Int32, offset: Int32) {
        context?.evaluateScript("mem[\(offset)]=\(value)")
    }

    func write(bytes: [UInt8], offset: Int32) {
        var src = "(()=>{let mem=new Uint8Array(inst.exports.memory.buffer,\(offset),\(bytes.count));"
        for (i, byte) in bytes.enumerated() {
            src += "mem[\(i)]=\(byte);"
        }
        src += "})()"
        context?.evaluateScript(src)
    }

    func write(data: Data, offset: Int32) {
        write(bytes: [UInt8](data), offset: offset)
    }
}
