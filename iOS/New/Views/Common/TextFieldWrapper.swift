//
//  TextFieldWrapper.swift
//  Aidoku
//
//  Created by Skitty on 8/7/25.
//

import SwiftUI

struct TextFieldWrapper<Content: View>: View {
    var hasError: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(uiColor: .secondarySystemBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if hasError {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.red, lineWidth: 1)
            }
        }
    }
}
