//
//  MangaCarouselView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/14/22.
//

import SwiftUI

struct MangaCarouselView: View {
    let title: String
    let manga: [Manga]
    
    var body: some View {
        Text(title)
            .fontWeight(.medium)
            .padding(.horizontal)
            .padding(.top, 4)
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
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }
}
