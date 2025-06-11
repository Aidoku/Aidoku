//
//  BetterBorderedButtonStyle.swift
//  Aidoku
//
//  Created by Skitty on 5/11/25.
//

import SwiftUI

// same as BorderedButtonStyle, but with a different background color
struct BetterBorderedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let backgroundOpacity = configuration.isPressed ? (colorScheme == .dark ? 1.4 : 0.65) : 1
        let labelOpacity = configuration.isPressed && colorScheme == .light ? 0.75 : 1
        let foregroundColor = configuration.isPressed && colorScheme == .dark
            ? Color(uiColor: .accent).mix(with: .white, by: 0.1)
            : Color.accentColor

        HStack {
            configuration.label
                .opacity(labelOpacity)
        }
        .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
        .foregroundStyle(foregroundColor)
        .background(Color(uiColor: .tertiarySystemFill).opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Color {
    func mix(with color: Color, by percentage: Double) -> Color {
        let clampedPercentage = min(max(percentage, 0), 1)

        let components1 = UIColor(self).cgColor.components!
        let components2 = UIColor(color).cgColor.components!

        let red = (1 - clampedPercentage) * components1[0] + clampedPercentage * components2[0]
        let green = (1 - clampedPercentage) * components1[1] + clampedPercentage * components2[1]
        let blue = (1 - clampedPercentage) * components1[2] + clampedPercentage * components2[2]
        let alpha = (1 - clampedPercentage) * components1[3] + clampedPercentage * components2[3]

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
