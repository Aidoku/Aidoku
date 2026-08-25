//
//  WKWebView+ContentWorld.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//
//  Named for what it adds rather than for the type: Extensions/WebKit/WKWebView.swift already
//  exists, and two source files sharing a basename collide in a target's build outputs.
//

import WebKit

extension WKWebView {
    // the compiler-generated async overload of evaluateJavaScript(_:in:in:) resolves to () for
    // every content world no matter what the script returns, so the completion-handler form is
    // wrapped instead. the label differs from the framework's so the two do not overload
    @MainActor
    func evaluateJavaScript(_ script: String, contentWorld: WKContentWorld) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script, in: nil, in: contentWorld) { result in
                switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}
