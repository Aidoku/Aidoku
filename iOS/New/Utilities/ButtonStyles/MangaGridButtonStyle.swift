//
//  MangaGridButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 10/13/23.
//

import SwiftUI

struct MangaGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                (configuration.isPressed ? Color.black.opacity(0.5) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            )
    }
}
