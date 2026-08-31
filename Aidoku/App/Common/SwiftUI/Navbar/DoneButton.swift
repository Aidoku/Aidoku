//
//  DoneButton.swift
//  Aidoku
//
//  Created by Skitty on 9/21/25.
//

import SwiftUI

struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .confirm) {
                action()
            }
        } else {
            Button {
                action()
            } label: {
                Text(NSLocalizedString("DONE")).bold()
            }
        }
    }
}
