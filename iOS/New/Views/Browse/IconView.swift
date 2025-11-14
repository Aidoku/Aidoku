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
    var iconSize: CGFloat = 48

    var body: some View {
        SourceImageView(
            imageUrl: imageUrl?.absoluteString ?? "",
            width: iconSize,
            height: iconSize
        )
        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225))
        .overlay(
            RoundedRectangle(cornerRadius: iconSize * 0.225)
                .strokeBorder(Color(uiColor: UIColor.quaternarySystemFill), lineWidth: 1)
        )
    }
}

struct SourceIconView: View {
    let sourceId: String
    var imageUrl: URL?
    var iconSize: CGFloat = 48

    var body: some View {
        if let imageUrl {
            IconView(
                imageUrl: imageUrl,
                iconSize: iconSize
            )
        } else {
            let imageName = switch sourceId {
                case LocalSourceRunner.sourceKey: "local"
                case let x where x.hasPrefix("kavita"): "kavita"
                case let x where x.hasPrefix("komga"): "komga"
                default: "MangaPlaceholder"
            }
            Image(imageName)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225))
                .overlay(
                    RoundedRectangle(cornerRadius: iconSize * 0.225)
                        .strokeBorder(Color(uiColor: UIColor.quaternarySystemFill), lineWidth: 1)
                )
        }
    }
}
