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
    private let chaptersLimit = 5

    var manga: Manga?
    let updates: [MangaUpdatesView.MangaUpdateInfo]
    let count: Int
    let viewed: Bool

    init(updates: [MangaUpdatesView.MangaUpdateInfo]) {
        self.updates = updates
        self.count = updates.count
        self.manga = updates.first?.manga
        self.viewed = updates.first?.viewed == true
    }

    var body: some View {
        HStack(alignment: count == 1 ? .center : .top) {
            LazyImage(url: manga?.coverUrl) { state in
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
                Text(manga?.title ?? "")
                    .foregroundColor(viewed ? .secondary : .primary)
                    .lineLimit(2)

                ForEach(updates.prefix(chaptersLimit)) { item in
                    if let chapterTitle = item.chapter?.makeTitle() {
                        Text(chapterTitle)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if count > chaptersLimit {
                    Text("\(count - chaptersLimit)_PLUS_MORE")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
