//
//  IconView.swift
//  Aidoku
//
//  Created by Skitty on 3/23/24.
//

import SwiftUI
import NukeUI

struct IconView: View {
    let imageUrl: URL?

    static let iconSize: CGFloat = 48

    var body: some View {
        SourceImageView(
            imageUrl: imageUrl?.absoluteString ?? "",
            width: Self.iconSize,
            height: Self.iconSize
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.iconSize * 0.225))
        .overlay(
            RoundedRectangle(cornerRadius: Self.iconSize * 0.225)
                .strokeBorder(Color(uiColor: UIColor.quaternarySystemFill), lineWidth: 1)
        )
    }
}

struct SourceIconView: View {
    let sourceId: String
    let imageUrl: URL?

    var body: some View {
        if let imageUrl {
            IconView(imageUrl: imageUrl)
        } else {
            let imageName = switch sourceId {
                case LocalSourceRunner.sourceKey: "local"
                case let x where x.hasPrefix("kavita"): "kavita"
                case let x where x.hasPrefix("komga"): "komga"
                default: "MangaPlaceholder"
            }
            Image(imageName)
                .resizable()
                .frame(width: IconView.iconSize, height: IconView.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: IconView.iconSize * 0.225))
                .overlay(
                    RoundedRectangle(cornerRadius: IconView.iconSize * 0.225)
                        .strokeBorder(Color(uiColor: UIColor.quaternarySystemFill), lineWidth: 1)
                )
        }
    }
}
