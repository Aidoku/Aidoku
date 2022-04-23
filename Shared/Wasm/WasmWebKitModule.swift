//
//  WasmWebKitModule.swift
//  Aidoku
//
//  Created by Skitty on 4/22/22.
//

import Foundation

public class WasmWebKitModule {

    let name: String
    let manager: WasmWebKitManager
    let module: [UInt8]

    var importCache: [String: [String: String]] = [:]
    var functionCache: [String: Any] = [:]
    var moduleCreated = false
    var instanceCreated = false

    init(manager: WasmWebKitManager, module: [UInt8]) {
        self.name = "__wasm_module_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        self.manager = manager
        self.module = module

        Task {
            await createModule()
        }
    }

    @MainActor
    func createModule() async {
        // create wasm module
//        let byteArray = module.map { String($0) }.joined(separator: ",")
//        _ = try? await manager.webView!.evaluateJavaScript("let \(name)_mod = new WebAssembly.Module(new Uint8Array([\(byteArray)]));1;")
//        self.moduleCreated = true
    }

    @MainActor
    func createInstance() async {
        if !self.moduleCreated {
            let byteArray = module.map { String($0) }.joined(separator: ",")
            // swiftlint:disable:next force_try
            _ = try! await manager.webView!.evaluateJavaScript("let \(name)_mod = new WebAssembly.Module(new Uint8Array([\(byteArray)]));1;")
            self.moduleCreated = true
        }
        // create imported functions
        for function in functionCache.keys {
            let src = """
                let \(function)=(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z)=>{
                    return window.prompt('\(function)',
                                         a+'|'+b+'|'+c+'|'+d+'|'+e+'|'+f+'|'+g+'|'+h+'|'+i+'|'+j+'|'+k
                                         +'|'+l+'|'+m+'|'+n+'|'+o+'|'+p+'|'+q+'|'+r+'|'+s+'|'+t+'|'+u
                                         +'|'+v+'|'+w+'|'+x+'|'+y+'|'+z);
                };1;
            """
            _ = try? await manager.webView!.evaluateJavaScript(src)
        }

        // create wasm import object
        var importSrc = "let \(name)_imports={"
        importSrc += importCache.map {
            "\($0.key):{\(($0.value).map { "\($0.key):\($0.value)" }.joined(separator: ","))}"
        }.joined(separator: ",")
        importSrc += "};1;"
        // swiftlint:disable:next force_try
        _ = try! await manager.webView!.evaluateJavaScript(importSrc)

        // instanciate wasm module
        // swiftlint:disable:next force_try
        _ = try! await manager.webView!.evaluateJavaScript("let \(name)=new WebAssembly.Instance(\(name)_mod, \(name)_imports);1;") //
        instanceCreated = true
    }

    public func addImportHandler(named: String, namespace: String, block: Any) {
        // save function in cache
        let importName = "__wasm_function_\(name)_\(namespace)_\(named)"
        functionCache[importName] = block

        // add to wasm import object
        var moduleImports = importCache[namespace] ?? [:]
        moduleImports[named] = importName
        importCache[namespace] = moduleImports
    }

    @MainActor
    public func call(_ function: String, args: [WasmTypeProtocol] = []) async -> Int32? {
        if !instanceCreated {
            await createInstance()
        }
        // call exported function
        // swiftlint:disable:next force_try
        let result = try! await manager.webView!.evaluateJavaScript(
            "\(name).exports.\(function)(\(args.map { $0.toString() }.joined(separator: ",")));"
        )
        return result as? Int32
    }

    func evaluateSynchronously(_ js: String) -> Any? {
        var result: Any?
        var keepAlive = true
        manager.webView!.evaluateJavaScript(js) { res, err in
            result = res
            if err != nil {
                print(err!)
            }
            keepAlive = false
        }
        // FIXME: BIG WARNING: THIS IS A DEADLOCK
        while keepAlive && RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) {}
        return result
    }

    func readBytes(offset: Int32, length: Int32) -> [UInt8]? {
        let src = "new Uint8Array(\(name).exports.memory.buffer, \(offset), \(length))"
        let res = evaluateSynchronously(src) as? [String: Any]
        return res?.keys.sorted(by: { Int($0) ?? 0 < Int($1) ?? 0 }).compactMap { res?[$0] as? UInt8 }
    }

    func readValues(offset: Int32, length: Int32) -> [Int32]? {
        let src = "new Int32Array(\(name).exports.memory.buffer, \(offset), \(length))"
        let res = evaluateSynchronously(src) as? [String: Any]
        return res?.keys.sorted(by: { Int($0) ?? 0 < Int($1) ?? 0 }).compactMap { res?[$0] as? Int32 }
    }

    func readValue(offset: Int32) -> Int32? {
        let src = "new Int32Array(\(name).exports.memory.buffer, \(offset), 1)[0]"
        return evaluateSynchronously(src) as? Int32
    }

    func readString(offset: Int32, length: Int32) -> String? {
        let result = evaluateSynchronously("String.fromCharCode.apply(null,new Uint8Array(\(name).exports.memory.buffer,\(offset),\(length)));")
        print("read: \(result ?? "nil")")
        if let result = result as? String {
            return result
        } else if let result = result as? Int {
            return String(result)
        } else {
            return nil
        }
    }

    func readData(offset: Int32, length: Int32) -> Data? {
        if let bytes = readBytes(offset: offset, length: length) {
            return Data(bytes)
        }
        return nil
    }

    func write(value: Int32, offset: Int32) {
        manager.webView!.evaluateJavaScript("(()=>{let mem=new Int32Array(\(name).exports.memory.buffer,\(offset),1);mem[0]=\(value);})")
    }

    func write(bytes: [UInt8], offset: Int32) {
        var src = "(()=>{let mem=new Uint8Array(\(name).exports.memory.buffer,\(offset),\(bytes.count));"
        for (i, byte) in bytes.enumerated() {
            src += "mem[\(i)]=\(byte);"
        }
        src += "})();1;"
        manager.webView!.evaluateJavaScript(src)
    }

    func write(data: Data, offset: Int32) {
        write(bytes: [UInt8](data), offset: offset)
    }
}
