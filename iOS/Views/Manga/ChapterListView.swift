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
    @State var volumes: [Volume]
    @State var readHistory: [String: Bool]
    
    @State var selectedChapter: Chapter?
    @State var sortSelection = 0
    
    init(manga: Manga, chapters: [Chapter], readHistory: [String: Bool]) {
        self.chapters = chapters
        self.manga = manga
        self.readHistory = readHistory
        
        let volumeNumbers = chapters.map { $0.chapterNum == 0 ? -2 : $0.volumeNum ?? -1 }.uniqued()
        var newVolumes = [Volume]()
        for num in volumeNumbers {
            let actual = num < 0 ? nil : num
            let title = num < -1 ? "Volume 0" : num < 1 ? "No Volume" : "Volume \(num)"
            newVolumes.append(Volume(
                title: title,
                sortNumber: num == 0 ? Int.max : num,
                chapters: chapters.filter { num < -1 ? $0.chapterNum == 0 : $0.volumeNum == actual && $0.chapterNum > 0 }
            ))
        }
        self.volumes = newVolumes
    }
    
    var body: some View {
        List {
            ForEach(volumes, id: \.self) { volume in
                Section(header: Text(volume.title)) {
                    ForEach(volume.chapters, id: \.self) { chapter in
                        Button {
                            selectedChapter = chapter
                        } label: {
                            ChapterListCell(chapter: chapter, readHistory: $readHistory)
                        }
                        .contextMenu {
                            if readHistory[chapter.id] ?? false {
                                Button {
                                    DataManager.shared.removeHistory(forManga: manga, chapter: chapter)
                                    updateReadHistory()
                                } label: {
                                    Text("Mark as Unread")
                                }
                            } else {
                                Button {
                                    DataManager.shared.addReadHistory(forManga: manga, chapter: chapter)
                                    updateReadHistory()
                                } label: {
                                    Text("Mark as Read")
                                }
                            }
                        }
                    }
                }
            }
        }
        .id(UUID())
        .listStyle(.plain)
        .navigationTitle("Chapters")
        .toolbar {
            Menu {
                Picker("Sort", selection: $sortSelection) {
                    Text("Ascending").tag(0)
                    Text("Descending").tag(1)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
        }
        .onChange(of: sortSelection) { newValue in
            if newValue == 0 {
                for (index, _) in volumes.enumerated() {
                    volumes[index].chapters.sort {
                        $0.chapterNum < $1.chapterNum
                    }
                }
                volumes.sort {
                    $0.sortNumber < $1.sortNumber
                }
            } else {
                for (index, _) in volumes.enumerated() {
                    volumes[index].chapters.sort {
                        $0.chapterNum > $1.chapterNum
                    }
                }
                volumes.sort {
                    $0.sortNumber > $1.sortNumber
                }
            }
        }
        .fullScreenCover(item: $selectedChapter, onDismiss: {
            updateReadHistory()
        }, content: { item in
            ReaderView(manga: manga, chapter: item, startPage: DataManager.shared.currentPage(forManga: manga.id, chapter: item.id))
                .edgesIgnoringSafeArea(.all)
        })
    }
    
    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(forManga: manga)
    }
}
