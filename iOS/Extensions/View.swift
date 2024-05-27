//
//  View.swift
//  Aidoku
//
//  Created by Skitty on 7/21/22.
//

import SwiftUI

struct NoHitTesting: ViewModifier {
    func body(content: Content) -> some View {
        SwiftUIWrapper { content }.allowsHitTesting(false)
    }
}

struct SwiftUIWrapper<T: View>: UIViewControllerRepresentable {
    let content: () -> T
    func makeUIViewController(context: Context) -> UIHostingController<T> {
        UIHostingController(rootView: content())
    }
    func updateUIViewController(_ uiViewController: UIHostingController<T>, context: Context) {}
}

extension View {
    func userInteractionDisabled() -> some View {
        self.modifier(NoHitTesting())
    }
}

extension View {
    @ViewBuilder
    func refreshableCompat(action: @Sendable @escaping () async -> Void) -> some View {
        if #available(iOS 15.0, *) {
            self.refreshable(action: action)
        } else {
            self
        }
    }

    @ViewBuilder
    func hideListRowSeparator() -> some View {
        if #available(iOS 15.0, *) {
            self.listRowSeparator(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func hideListSectionSeparator() -> some View {
        if #available(iOS 15.0, *) {
            self.listSectionSeparator(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func offsetListSeparator() -> some View {
        if #available(iOS 16.0, *) {
            self.alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        } else {
            self
        }
    }
}
