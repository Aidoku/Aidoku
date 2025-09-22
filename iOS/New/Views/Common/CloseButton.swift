//
//  CloseButton.swift
//  Aidoku
//
//  Created by Skitty on 12/31/24.
//

import SwiftUI

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close) {
                action()
            }
        } else {
            CloseButtonUIKit(action: action)
        }
    }
}

struct CloseButtonUIKit: UIViewRepresentable {
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func makeUIView(context: Context) -> UIButton {
        UIButton(type: .close, primaryAction: UIAction { _ in action() })
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
