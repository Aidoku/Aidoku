//
//  SwiftUINavigationView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/6/23.
//

import SwiftUI

struct SwiftUINavigationView: View {

    @Environment(\.presentationMode) var presentationMode

    var rootView: AnyView

    var closeButtonTitle: String = NSLocalizedString("CANCEL", comment: "")

    var body: some View {
        NavigationView {
            rootView
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(closeButtonTitle) {
                            dismiss()
                        }
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    func dismiss() {
        if #available(iOS 15.0, *) {
            presentationMode.wrappedValue.dismiss()
        } else {
            // for ios 14
            if var topController = UIApplication.shared.windows.first!.rootViewController {
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }
                topController.dismiss(animated: true)
            }
        }
    }
}
