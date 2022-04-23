//
//  WasmWebKitManager.swift
//  Aidoku
//
//  Created by Skitty on 4/22/22.
//

import Foundation
import WebKit

class WasmWebKitManager: NSObject {

    static var shared = WasmWebKitManager()

    var webView: WKWebView?
    var modules: [WasmWebKitModule] = []

    override init() {
        super.init()
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView?.uiDelegate = self
    }

    func createModule(_ bytes: [UInt8]) -> WasmWebKitModule {
        let module = WasmWebKitModule(manager: self, module: bytes)
        modules.append(module)
        return module
    }
}

extension WasmWebKitManager: WKUIDelegate {

    @MainActor
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        // arguments in defaultText split by pipe
        let arguments = (defaultText ?? "").split(separator: "|").filter({ $0 != "undefined" }).compactMap { Int32($0) }

        // find function to call
        for module in modules {
            for function in module.functionCache.keys where function == prompt {
                if let fun = module.functionCache[function] as? WasmWrapperReturningFunction {
                    return String(fun(arguments) as? Int32 ?? -1)
                } else if let fun = module.functionCache[function] as? WasmWrapperVoidFunction {
                    fun(arguments)
                }
                return nil
            }
        }
        return nil
    }
}
