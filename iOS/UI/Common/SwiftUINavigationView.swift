//
//  SwiftUINavigationView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI

struct SwiftUINavigationView<Content: View>: View {
    let rootView: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            rootView
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            dismiss()
                        }
                    }
                }
        }
    }
}
