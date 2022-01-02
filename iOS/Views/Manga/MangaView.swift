//
//  MangaView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import SwiftUI
import SwiftUIX
import Kingfisher

struct MangaView: View {
    
    @State var manga: Manga
    
    @State var fulldesc = false
    @State var descriptionLoaded = false
    @State var chaptersLoaded = false
    @State var inLibrary: Bool = false
    
    @State var showReader = false
    
    @State var chapters: [Chapter] = []
    @State var readHistory: [String: Bool] = [:]
    
    @State var selectedChapter: Chapter?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    KFImage(URL(string: manga.thumbnailURL ?? ""))
                        .resizable()
                        .frame(width: 94, height: 140)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        Text(manga.title)
                            .font(.system(size: 24, weight: .medium))
                            .lineLimit(2)
                        Text(manga.author ?? "Unknown Author")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        HStack {
                            Button {
                                selectedChapter = chapters.last(where: { readHistory[$0.id] ?? false }) ?? chapters.first
                            } label: {
                                Image(systemName: "play.fill")
                                Text("Read")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .frame(height: 36)
                            .background(.accentColor)
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .padding()
                
                HStack {
                    Text("Description")
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Button {
                        withAnimation {
                            fulldesc.toggle()
                        }
                    } label: {
                        Text(fulldesc ? "Show Less" : "Show More")
                    }
                    .animation(nil)
                }
                .padding(.horizontal)
                if !descriptionLoaded {
                    HStack {
                        Spacer()
                        ActivityIndicator()
                            .transition(.opacity)
                        Spacer()
                    }
                } else {
                    Text(manga.description ?? "No Description")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .lineLimit(fulldesc ? 50 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .transition(.move(edge: .top))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(manga.categories ?? [], id: \.self) { category in
                            Text(category)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(4)
                                .padding(.horizontal, 8)
                                .background(Color.tertiaryFill)
                                .cornerRadius(100)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
                
                HStack {
                    Text("Chapters")
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    NavigationLink {
                        ChapterListView(manga: manga, chapters: chapters, readHistory: readHistory)
                    } label: {
                        Text("Show All")
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
                                        
                if !chaptersLoaded {
                    HStack {
                        Spacer()
                        ActivityIndicator()
                            .transition(.opacity)
                        Spacer()
                    }
                } else if chapters.isEmpty {
                    HStack {
                        Spacer()
                        Text("No Chapters")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ForEach(chapters.prefix(5)) { chapter in
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
                Spacer(minLength: 16)
            }
            .frame(alignment: .center)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if inLibrary || DataManager.shared.manga.contains(manga) {
                    if #available(iOS 15, *) {
                        Button {
                            DataManager.shared.deleteManga(manga)
                            inLibrary = DataManager.shared.manga.contains(manga)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .background(.tertiaryFill)
                        .clipShape(Circle())
                        .frame(width: 28, height: 28)
                        .padding(.trailing, 12)
                    } else {
                        Button {
                            DataManager.shared.deleteManga(manga)
                            inLibrary = DataManager.shared.manga.contains(manga)
                        } label: {
                            Image(systemName: "bookmark.fill")
                        }
                    }
                } else {
                    if #available(iOS 15, *) {
                        Button {
                            _ = DataManager.shared.add(manga: manga)
                            inLibrary = DataManager.shared.manga.contains(manga)
                        } label: {
                            Image(systemName: "plus")
                                .padding(.leading, 2)
                                .padding(.trailing, -5)
                                .font(.system(size: 10, weight: .heavy))
                            Text("Add")
                                .padding(.trailing, 6)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .background(.tertiaryFill)
                        .cornerRadius(14)
                        .frame(width: 67, height: 28)
                        .padding(.trailing, 12)
                    } else {
                        Button {
                            _ = DataManager.shared.add(manga: manga)
                            inLibrary = DataManager.shared.manga.contains(manga)
                        } label: {
                            Image(systemName: "bookmark")
                        }
                    }
                }
                if #available(iOS 15, *) {
                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .padding(.trailing, 8)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .background(.tertiaryFill)
                    .clipShape(Circle())
                    .frame(width: 28, height: 28)
                } else {
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedChapter, onDismiss: {
            updateReadHistory()
        }, content: { item in
            ReaderView(manga: manga, chapter: item, startPage: DataManager.shared.currentPage(forManga: manga.id, chapter: item.id))
                .edgesIgnoringSafeArea(.all)
        })
        .onAppear {
            Task {
                await fetchManga()
            }
        }
    }
    
    func fetchManga() async {
        inLibrary = DataManager.shared.manga.contains(manga)
        
        let provider = ProviderManager.shared.provider(for: manga.provider)
        
        let newManga = await provider.getMangaDetails(id: manga.id)
        manga = manga.copy(from: newManga)
        withAnimation(.easeInOut(duration: 0.3)) {
            descriptionLoaded = true
        }
        updateReadHistory()
        chapters = await provider.getChapterList(id: manga.id)
        withAnimation(.easeInOut(duration: 0.3)) {
            chaptersLoaded = true
        }
        manga.thumbnailURL = await provider.getMangaCoverURL(manga: manga, override: true)
    }
    
    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(forMangaId: manga.id)
    }
}

