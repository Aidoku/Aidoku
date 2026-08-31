//
//  DarkOverlayButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 9/30/23.
//

import SwiftUI

// shows a dark overlay when pressed
struct DarkOverlayButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    Rectangle()
                        .fill(Color.black)
                        .opacity(colorScheme == .dark ? 0.5 : 0.3)
                }
            }
    }
}
