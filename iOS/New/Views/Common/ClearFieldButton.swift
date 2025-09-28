//
//  ClearFieldButton.swift
//  Aidoku
//
//  Created by Skitty on 8/7/25.
//

import SwiftUI

struct ClearFieldButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        .tint(Color.tertiaryLabel)
    }
}
