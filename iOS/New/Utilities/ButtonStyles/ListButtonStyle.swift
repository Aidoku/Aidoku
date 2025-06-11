//
//  ListButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 2/1/25.
//

import SwiftUI

struct ListButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
            .foregroundStyle(.tint)
    }
}
