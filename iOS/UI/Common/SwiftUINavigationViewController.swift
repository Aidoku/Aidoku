//
//  SwiftUINavigationViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI

class SwiftUINavigationViewController<Content: View>: UINavigationController {
    let path = NavigationCoordinator(rootViewController: nil)

    init (rootView: Content) {
        super.init(rootViewController: UIHostingController(rootView: ModelWrapper(rootView: rootView, path: path)))
        path.rootViewController = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ModelWrapper<Content: View>: View {
    let rootView: Content
    let path: NavigationCoordinator

    var body: some View {
        rootView
            .environmentObject(path)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        path.dismiss()
                    }
                }
            }
    }
}
