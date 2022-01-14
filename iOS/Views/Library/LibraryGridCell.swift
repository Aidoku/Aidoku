//
//  LibraryGridCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import Kingfisher

struct LibraryGridCell: View {
    
    let manga: Manga
    
    var body: some View {
        KFImage(URL(string: manga.thumbnailURL ?? ""))
            .resizable()
            .aspectRatio(2/3, contentMode: .fit)
            .cornerRadius(5)
            .overlay {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .clear, location: 0.4)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                    .cornerRadius(5)
                    .opacity(0.7)
            }
            .overlay(alignment: .bottomLeading) {
                Text(manga.title ?? "Unknown Title")
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(8)
            }
    }
}

