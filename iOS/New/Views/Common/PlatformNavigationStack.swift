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

#if os(macOS)
    @State private var path = NavigationPath()
#endif

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
#if os(macOS)
            NavigationStack(path: $path.animation(.default)) {
                content
            }
#else
            NavigationStack {
                content
            }
#endif
        } else {
#if !os(macOS)
            NavigationView {
                content
            }
            .navigationViewStyle(.stack)
#else
            NavigationView {
                content
            }
#endif
        }
    }
}
