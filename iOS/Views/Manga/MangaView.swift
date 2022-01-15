//
//  MangaView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import SwiftUI
import SwiftUIX
import Kingfisher

struct AnimatingWidth: AnimatableModifier {
    var width: CGFloat = 0

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: width)
    }
}

struct MangaView: View {
    
    @State var manga: Manga
    
    @State var chaptersLoaded = false
    @State var inLibrary: Bool = false
    
    @State var showReader = false
    
    @State var chapters: [Chapter] = []
    @State var readHistory: [String: Bool] = [:]
    
    @State var selectedChapter: Chapter?
    
    @State var descriptionLoaded = false
    @State var descriptionExpanded = false
    @State var descriptionLineCount = 4
    @State var isAnimatingDescription = false
    
    @State var showingAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    KFImage(URL(string: manga.thumbnailURL ?? ""))
                        .resizable()
                        .frame(width: 100, height: 150)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        Text(manga.title ?? "Unknown Title")
                            .font(.system(size: 24, weight: .medium))
                            .lineLimit(3)
                        Text(manga.author ?? "")
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
                            .cornerRadius(5)
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
                            animateDescription()
                        }
                    } label: {
                        Text(descriptionExpanded ? "Show Less" : "Show More")
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
                        .lineLimit(descriptionLineCount)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        .transition(.move(edge: .top))
                }
                if let categories = manga.categories {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(categories, id: \.self) { category in
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
                                        if let title = chapter.title {
                                            Text(title)
                                                .foregroundColor(readHistory[chapter.id] ?? false ? .secondaryLabel : .label)
                                                .lineLimit(1)
                                        } else {
                                            Text("Chapter \(chapter.chapterNum, specifier: "%g")")
                                                .foregroundColor(readHistory[chapter.id] ?? false ? .secondaryLabel : .label)
                                                .lineLimit(1)
                                        }
                                        if chapter.title != nil {
                                            Text("Chapter \(chapter.chapterNum, specifier: "%g")")
                                                .foregroundColor(.secondaryLabel)
                                                .lineLimit(1)
                                        }
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
                                    DataManager.shared.removeHistory(manga: manga, chapter: chapter)
                                    updateReadHistory()
                                } label: {
                                    Text("Mark as Unread")
                                }
                            } else {
                                Button {
                                    DataManager.shared.addReadHistory(manga: manga, chapter: chapter)
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
                if #available(iOS 15, *) {
                    ZStack(alignment: .trailing) {
                        Button {
                            if inLibrary {
                                DataManager.shared.delete(manga: manga)
                            } else {
                                _ = DataManager.shared.add(manga: manga)
                            }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inLibrary = DataManager.shared.contains(manga: manga)
                            }
                        } label: {
                            if inLibrary {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding([.leading, .trailing], -3)
                            } else {
                                HStack {
                                    Image(systemName: "plus")
                                        .padding(.leading, 2)
                                        .padding(.trailing, -5)
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("Add")
                                        .padding(.trailing, 6)
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                        }
                    }
                    .background(.tertiaryFill)
                    .cornerRadius(14)
                    .frame(height: 28)
                    .modifier(AnimatingWidth(width: inLibrary ? 28 : 67))
                    .padding(.trailing, 12)
                } else {
                    Button {
                        if inLibrary {
                            DataManager.shared.delete(manga: manga)
                        } else {
                            _ = DataManager.shared.add(manga: manga)
                        }
                        inLibrary = DataManager.shared.contains(manga: manga)
                    } label: {
                        Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
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
            ReaderView(manga: manga, chapter: item, startPage: DataManager.shared.currentPage(manga: manga, chapterId: item.id))
                .edgesIgnoringSafeArea(.all)
        })
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Missing Source"),
                message: Text("The original source seems to be missing for this Manga. Please redownload it or remove this title from your library."),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            inLibrary = DataManager.shared.contains(manga: manga)
            if !chaptersLoaded {
                Task {
                    await fetchManga()
                }
            } else {
                updateReadHistory()
            }
        }
    }
    
    func animateDescription() {
        guard !isAnimatingDescription else { return } // Check not currently animating
        descriptionExpanded.toggle()
        isAnimatingDescription = true

        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            if descriptionExpanded {
                descriptionLineCount += 1
                if descriptionLineCount >= 15 { // max lines
                    timer.invalidate()
                    isAnimatingDescription = false
                }
            } else {
                descriptionLineCount -= 1
                if descriptionLineCount <= 4 { // max lines
                    timer.invalidate()
                    isAnimatingDescription = false
                }
            }
        }
        timer.fire()
    }
    
    func fetchManga() async {
        guard let source = SourceManager.shared.source(for: manga.provider) else {
            manga.description = "No Description"
            chapters = []
            withAnimation(.easeInOut(duration: 0.3)) {
                descriptionLoaded = true
                chaptersLoaded = true
            }
            showingAlert = true
            return
        }
        
        if let newManga = try? await source.getMangaDetails(manga: manga) {
            manga = manga.copy(from: newManga)
            withAnimation(.easeInOut(duration: 0.3)) {
                descriptionLoaded = true
            }
            updateReadHistory()
            chapters = (try? await source.getChapterList(manga: manga)) ?? []
            withAnimation(.easeInOut(duration: 0.3)) {
                chaptersLoaded = true
            }
        }
    }
    
    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(manga: manga)
    }
}

