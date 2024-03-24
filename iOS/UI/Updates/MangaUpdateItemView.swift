//
//  MangaUpdateItemView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 10/02/2024.
//

import SwiftUI
import NukeUI

struct MangaUpdateItemView: View {

    private let coverWidth: CGFloat = 56
    private let coverHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 5

    let item: MangaUpdatesView.MangaUpdateInfo

    var body: some View {
        HStack {
            LazyImage(url: item.manga.coverUrl) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image("MangaPlaceholder")
                }
            }
            .frame(width: coverWidth, height: coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
            .padding(.trailing, 6)

            VStack(alignment: .leading) {
                Text(item.manga.title ?? "")
                    .foregroundColor(item.viewed ? .secondary : .primary)
                    .lineLimit(2)

                if let chapterTitle = item.chapter?.makeTitle() {
                    Text(chapterTitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }// :HStack
    }
}
