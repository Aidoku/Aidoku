//
//  ListButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 2/1/25.
//

import SwiftUI

struct ListButtonStyle: ButtonStyle {
    var tint: Bool = true

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if configuration.isPressed {
#if !os(macOS)
                        Color(UIColor.systemGray4)
                            .animation(nil, value: configuration.isPressed)
#else
                        Color(UIColor.systemGray)
                            .animation(nil, value: configuration.isPressed)
#endif
                    } else {
                        Color(UIColor.systemBackground)
                            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
                    }
                }
            )
            .contentShape(Rectangle())
        if tint {
            label.foregroundStyle(.tint)
        } else {
            label
        }
    }
}
