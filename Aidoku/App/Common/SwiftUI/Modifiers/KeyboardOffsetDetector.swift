//
//  KeyboardOffsetDetector.swift
//  Aidoku
//
//  Created by Skitty on 11/16/25.
//

import SwiftUI

@available(iOS 16.0, *)
private struct KeyboardOffsetDetector: ViewModifier {
    @Binding var offset: CGFloat

    @State private var bottomInsetWithoutKeyboard: CGFloat?
    @State private var bottomInsetWithKeyboard: CGFloat?

    private var keyboardOffset: CGFloat {
        if let bottomInsetWithoutKeyboard, let bottomInsetWithKeyboard {
            bottomInsetWithKeyboard - bottomInsetWithoutKeyboard
        } else {
            0
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            Color.clear
                .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { bottomInset in
                    bottomInsetWithoutKeyboard = bottomInset
                }
                .ignoresSafeArea(.keyboard)
            Color.clear
                .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { bottomInset in
                    bottomInsetWithKeyboard = bottomInset
                }
            content
        }
        .onChange(of: keyboardOffset) { newVal in
            offset = newVal
        }
    }
}

extension View {
    func detectKeyboardOffset(_ offset: Binding<CGFloat>) -> some View {
        if #available(iOS 16.0, *) {
            return modifier(KeyboardOffsetDetector(offset: offset))
        } else {
            return self
        }
    }
}
