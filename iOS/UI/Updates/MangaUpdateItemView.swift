//
//  MangaUpdateItemView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 10/02/2024.
//

import AidokuRunner
import SwiftUI
import NukeUI

struct MangaUpdateItemView: View {
    private let coverWidth: CGFloat = 56
    private let coverHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 5
    private let chaptersLimit = 5

    var updates: [MangaUpdatesView.UpdateInfo]

    private let manga: AidokuRunner.Manga?
    private let count: Int
    private let viewed: Bool

    init(updates: [MangaUpdatesView.UpdateInfo]) {
        self.updates = updates
        self.count = updates.count
        self.manga = updates.first?.manga
        self.viewed = updates.first?.viewed == true
    }

    var body: some View {
        HStack(alignment: count == 1 ? .center : .top) {
            SourceImageView(
                source: manga.flatMap { SourceManager.shared.source(for: $0.sourceKey) },
                imageUrl: manga?.cover ?? "",
                width: coverWidth,
                height: coverHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
            .padding(.trailing, 6)

            VStack(alignment: .leading) {
                Text(manga?.title ?? "")
                    .foregroundStyle(viewed ? .secondary : .primary)
                    .lineLimit(2)

                ForEach(updates.prefix(chaptersLimit)) { item in
                    if let chapterTitle = item.chapter?.makeTitle() {
                        Text(chapterTitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if count > chaptersLimit {
                    Text(String(format: NSLocalizedString("%lld_PLUS_MORE"), count - chaptersLimit))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
