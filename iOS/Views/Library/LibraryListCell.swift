//
//  LibraryListCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import Kingfisher

struct LibraryListCell<Content, Content2>: View where Content: View, Content2: View {
    
    var manga: Manga
    let extraLabel: Content
    let menuContent: Content2
    
    init(manga: Manga, @ViewBuilder extraLabel: @escaping () -> Content, @ViewBuilder menuContent: @escaping () -> Content2) {
        self.manga = manga
        self.extraLabel = extraLabel()
        self.menuContent = menuContent()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                KFImage(URL(string: manga.thumbnailURL ?? ""))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 2/3*140)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(manga.title)
                        .foregroundColor(.label)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(manga.author ?? "Unknown Author")
                        .foregroundColor(.secondaryLabel)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    extraLabel
                }
                Spacer()
                VStack {
                    Spacer()
                    Menu {
                        menuContent
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondaryLabel)
                            .padding([.top, .leading], 12)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal)
            Divider()
                .padding(.leading)
                .padding(.leading)
                .padding(.leading, 2/3*140)
                .padding(.trailing)
        }
    }
}
