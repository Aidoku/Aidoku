//
//  MangaGridView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/5/23.
//

import SwiftUI
import NukeUI

struct MangaGridView: View {
    var title: String?
    var coverUrl: URL?

    var body: some View {
        LazyImage(url: coverUrl) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
            } else {
                Image("MangaPlaceholder")
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
            }
        }
        .animation(.default, value: coverUrl)
        .cornerRadius(5)
        .foregroundColor(Color(UIColor.red))
        .overlay(
            LinearGradient(gradient: Gradient(colors: [
                Color.black.opacity(0.01),
                Color.black.opacity(0.7)
            ]), startPoint: .top, endPoint: .bottom)
            .cornerRadius(5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(UIColor.quaternarySystemFill), lineWidth: 1)
        )
        .overlay(
            Text(title ?? "")
                .foregroundColor(.white)
                .font(.system(size: 15, weight: .medium))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .padding(8),
            alignment: .bottomLeading
        )
    }
}

struct PlaceholderMangaGridView: View {
    var body: some View {
        Image("MangaPlaceholder")
            .resizable()
            .aspectRatio(2/3, contentMode: .fill)
            .cornerRadius(5)
            .foregroundColor(Color(UIColor.systemFill))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
    }
}
