//
//  ChapterListCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/4/22.
//

import SwiftUI

struct ChapterListCell: View {
    let chapter: Chapter
    @Binding var readHistory: [String: Int]
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if let title = chapter.title {
                    Text(title)
                        .foregroundColor(readHistory[chapter.id] ?? 0 > 0 ? .secondaryLabel : .label)
                        .lineLimit(1)
                } else {
                    Text("Chapter \(chapter.chapterNum ?? 0, specifier: "%g")")
                        .foregroundColor(readHistory[chapter.id] ?? 0 > 0 ? .secondaryLabel : .label)
                        .lineLimit(1)
                }
                if chapter.title != nil {
                    Text("Chapter \(chapter.chapterNum ?? 0, specifier: "%g")")
                        .foregroundColor(.secondaryLabel)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.tertiaryLabel)
        }
    }
}
