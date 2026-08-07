//
//  RestoreListSelectionOnAppear.swift
//  Aidoku
//
//  Created by Amqx on 8/6/26.
//

import SwiftUI

// Remove then re-add an entry to force a re-render.
private struct RestoreListSelectionOnAppearModifier<Value: Hashable>: ViewModifier {
    @Binding var selection: Set<Value>

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // the first appearance renders from scratch, so there's nothing to restore
                guard appeared else {
                    appeared = true
                    return
                }
                guard let value = selection.first else { return }
                selection.remove(value)
                DispatchQueue.main.async {
                    selection.insert(value)
                }
            }
    }
}

extension View {
    func restoresListSelectionOnAppear<Value: Hashable>(_ selection: Binding<Set<Value>>) -> some View {
        modifier(RestoreListSelectionOnAppearModifier(selection: selection))
    }
}
