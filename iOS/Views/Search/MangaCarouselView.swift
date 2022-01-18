//
//  MangaCarouselView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/14/22.
//

import SwiftUI

struct MangaCarouselView<Content>: View where Content: View {
    let title: String
    let manga: [Manga]
    let viewMoreContent: Content
    
    init(title: String, manga: [Manga], @ViewBuilder viewMoreContent: @escaping () -> Content) {
        self.title = title
        self.manga = manga
        self.viewMoreContent = viewMoreContent()
    }
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            if manga.isEmpty {
                Text("No Results")
                    .foregroundColor(.secondaryLabel)
                    .padding(.bottom, 6)
            } else {
                NavigationLink("View More") {
                    viewMoreContent
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        if !manga.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(manga, id: \.self) { manga in
                        NavigationLink {
                            MangaView(manga: manga)
                        } label: {
                            LibraryGridCell(manga: manga)
                                .frame(width: 120)
                        }
                    }
                }
                .frame(height: 180 + 6)
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
    }
}
