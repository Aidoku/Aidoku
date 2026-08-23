//
//  UnavailableView.swift
//  Aidoku
//
//  Created by Skitty on 9/23/25.
//

import SwiftUI

struct UnavailableView: View {
    let title: String
    let systemImage: String
    var description: Text?

    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        } else {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))

                    if let description {
                        description
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    static func search(text: String) -> some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView.search(text: text)
        } else {
            Self(
                String(format: NSLocalizedString("NO_RESULTS_FOR_%@"), text),
                systemImage: "magnifyingglass",
                description: Text(NSLocalizedString("NO_RESULTS_TEXT"))
            )
        }
    }
}
