//
//  PlatformNavigationStack.swift
//  Aidoku
//
//  Created by Skitty on 10/6/23.
//

import SwiftUI

// uses navigationstack for newer ios, and uses a custom path for macos (in order to have animations)
struct PlatformNavigationStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            NavigationStack {
                content
            }
        } else {
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
        }
    }
}
