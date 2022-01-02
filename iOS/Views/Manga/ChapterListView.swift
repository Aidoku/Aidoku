//
//  ChapterListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/21.
//

import SwiftUI

struct ChapterListView: View {
    
    var manga: Manga
    var chapters: [Chapter]
    @State var readHistory: [String: Bool]
    
    @State var selectedChapter: Chapter?
    
    var body: some View {
        ScrollView {
            ForEach(chapters) { chapter in
                Button {
                    selectedChapter = chapter
                } label: {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(chapter.title)
                                    .foregroundColor(readHistory[chapter.id] ?? false ? .secondaryLabel : .label)
                                    .lineLimit(1)
                                Text("Chapter \(chapter.chapterNum, specifier: "%g")")
                                    .foregroundColor(.secondaryLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.tertiaryLabel)
                        }
                        .padding(.horizontal)
                        Divider()
                            .padding(.leading)
                    }
                }
                .contextMenu {
                    if readHistory[chapter.id] ?? false {
                        Button {
                            DataManager.shared.removeHistory(forChapterId: chapter.id)
                            updateReadHistory()
                        } label: {
                            Text("Mark as Unread")
                        }
                    } else {
                        Button {
                            DataManager.shared.addReadHistory(forMangaId: manga.id, chapterId: chapter.id)
                            updateReadHistory()
                        } label: {
                            Text("Mark as Read")
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        .navigationTitle("Chapters")
        .fullScreenCover(item: $selectedChapter, onDismiss: {
            updateReadHistory()
        }, content: { item in
            ReaderView(manga: manga, chapter: item, startPage: DataManager.shared.currentPage(forManga: manga.id, chapter: item.id))
                .edgesIgnoringSafeArea(.all)
        })
    }
    
    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(forMangaId: manga.id)
    }
}
