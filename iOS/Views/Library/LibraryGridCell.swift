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
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8.0)
                .overlay {
                    LinearGradient(gradient: Gradient(colors: [
                        Color.black.opacity(0.01),
                        Color.black.opacity(0.7)
                    ]), startPoint: .top, endPoint: .bottom)
                        .cornerRadius(8.0)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(manga.title)
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .padding(8)
                }
    }
}

