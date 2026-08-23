//
//  WKWebView+ContentWorld.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//
//  Named for what it adds rather than for the type, since `iOS/New/Extensions/WKWebView.swift`
//  already holds that name and two source files sharing a basename collide in a target's build
//  outputs.
//

import WebKit

extension WKWebView {
    /// Evaluates a script in a named content world and returns what it produced.
    ///
    /// The compiler-generated `async` overload of `evaluateJavaScript(_:in:in:)` resolves to `()`
    /// for every content world regardless of what the script returns, so the completion-handler
    /// form is wrapped instead. The plain `evaluateJavaScript(_:)` does return values, but it runs
    /// in the page world, which is unavailable to a caller that has disabled the page's own
    /// scripts and therefore needs a world of its own.
    ///
    /// The argument label differs from the framework's so that the two do not overload each other.
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
