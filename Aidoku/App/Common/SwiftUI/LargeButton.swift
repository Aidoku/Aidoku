//
//  LargeButton.swift
//  Aidoku
//
//  Created by Skitty on 9/24/25.
//

import SwiftUI

struct LargeButton<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Content

    var body: some View {
        Button {
            action()
        } label: {
            let padding: CGFloat = if #available(iOS 26.0, *) {
                // ios 26 uses larger list cells
                16
            } else {
                12
            }
            label
                .padding(padding)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
        }
        .background(
            Color(uiColor: .init(dynamicProvider: { collection in
                if collection.userInterfaceStyle == .dark {
                    .init(red: 0.20, green: 0.12, blue: 0.15, alpha: 1)
                } else {
                    .init(red: 0.95, green: 0.87, blue: 0.91, alpha: 1)
                }
            }))
            .opacity(0.8)
        )
        .padding(0)
        .listRowInsets(.zero)
        .listRowSpacing(0)
    }
}
