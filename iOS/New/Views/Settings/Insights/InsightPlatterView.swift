//
//  InsightPlatterView.swift
//  Aidoku
//
//  Created by Skitty on 12/17/25.
//

import SwiftUI

struct InsightPlatterView<Content: View>: View {
    @ViewBuilder var content: Content

    private let cornerRadius: CGFloat = 12

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}
