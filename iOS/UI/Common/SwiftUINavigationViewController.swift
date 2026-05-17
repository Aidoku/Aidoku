//
//  SwiftUINavigationViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI

class SwiftUINavigationViewController<Content: View>: UINavigationController {
    let path = NavigationCoordinator(rootViewController: nil)

    init(rootView: Content, addDismissButton: Bool = true) {
        let view = ModelWrapper(rootView: rootView, path: path, addDismissButton: addDismissButton)
        super.init(rootViewController: UIHostingController(rootView: view))
        path.rootViewController = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ModelWrapper<Content: View>: View {
    let rootView: Content
    let path: NavigationCoordinator
    let addDismissButton: Bool

    var body: some View {
        let view = rootView.environmentObject(path)
        if addDismissButton {
            view
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton {
                            path.dismiss()
                        }
                    }
                }
        } else {
            view
        }
    }
}
