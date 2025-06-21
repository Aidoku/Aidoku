//
//  GetButton.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import SwiftUI

struct GetButton: View {
    var action: () async -> Bool

    enum ButtonState: Equatable {
        case `default`
        case loading
        case error
    }

    @State private var buttonState: ButtonState = .default

    var body: some View {
        Button {
            Task {
                buttonState = .loading
                let success = await action()
                buttonState = success ? .default : .error
            }
        } label: {
            switch buttonState {
                case .default:
                    Text(NSLocalizedString("BUTTON_GET"))
                case .loading:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                case .error:
                    Text(NSLocalizedString("BUTTON_ERROR"))
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15).weight(.bold))
        .padding(.vertical, 4)
        .padding(.horizontal, buttonState == .loading ? 4 : 14)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 28))
//        .animation(.default, value: buttonState)
    }
}
