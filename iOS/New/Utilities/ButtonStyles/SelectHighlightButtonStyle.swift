//
//  SelectHighlightButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 4/28/25.
//

import SwiftUI

struct SelectHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                }
            }
    }
}
