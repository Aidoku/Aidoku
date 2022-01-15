//
//  LibraryView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import SwiftUIX
import Kingfisher
import CoreData

struct DropMenu: View {
    @Binding var selection: Int
    
    let options: [String]
    
    var body: some View {
        Menu {
            Picker("Sort", selection: $selection) {
                ForEach(0..<options.count) { i in
                    Text(options[i]).tag(i)
                }
            }
        } label: {
            Text("\(options[selection]) \(Image(systemName: "chevron.down"))")
                .foregroundColor(.label)
        }
    }
}

struct ChapterWithManga: Identifiable, Equatable {
    let id = UUID()
    let chapter: Chapter
    let manga: Manga
}

struct LibraryView: View {
    
    @AppStorage("libraryGrid") var grid = true
    @AppStorage("librarySort") var sortMethod = 0
    
    @State var manga: [Manga] = []
    @State var chapters: [String: [Chapter]] = [:]
    @State var readHistory: [String: [String: Bool]] = [:]
    
    @State var showingSettings: Bool = false
    @State var isEditing: Bool = false
    @State var searchText: String = ""
    
    @State var selectedChapter: ChapterWithManga?
    @State var selectedManga: Manga? = nil
    @State var openMangaInfoView: Bool = false
    
    @State var updatedLibrary: Bool = false
    
    var body: some View {
        NavigationView {
            if manga.isEmpty {
                VStack(spacing: 2) {
                    Text("Library Empty")
                        .font(.system(size: 25))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondaryLabel)
                        .padding(.top, -50)
                    Text("Add manga from the browse tab")
                    .padding(.top, -15)
                        .foregroundColor(.secondaryLabel)
                }
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large)
                .navigationSearchBar {
                    SearchBar("Search", text: $searchText, isEditing: $isEditing)
                        .showsCancelButton(isEditing)
                }
                .toolbar {
                    Button {
                        showingSettings.toggle()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            } else {
                ScrollView {
                    VStack {
                        HStack {
                            Text("Sort")
                                .foregroundColor(.secondary)
                                .padding(.trailing, -2)
                            DropMenu(selection: $sortMethod, options: [
                                "Recent",
                                "Title",
                                "Author"
                            ])
                                .animation(nil)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    grid.toggle()
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.label)
                                    .background(grid ? Color.clear : Color.secondaryFill)
                                    .cornerRadius(8)
                                    .padding(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        
                        if grid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                                ForEach(manga.filter {
                                    search(
                                        needle: searchText.lowercased(),
                                        haystack: $0.title?.lowercased() ?? ""
                                    )
                                }, id: \.self) { m in
                                    Button {
                                        if let c = getNextChapter(for: m) {
                                            selectedChapter = ChapterWithManga(
                                                chapter: c,
                                                manga: m
                                            )
                                        } else {
                                            selectedManga = m
                                            openMangaInfoView = true
                                        }
                                    } label: {
                                        LibraryGridCell(manga: m)
                                    }
                                    .contextMenu {
                                        Button {
                                            selectedManga = m
                                            openMangaInfoView = true
                                        } label: {
                                            Text("Manga Info")
                                            Image(systemName: "info.circle")
                                        }
                                        Button {
                                            DataManager.shared.delete(manga: m)
                                            loadManga()
                                        } label: {
                                            Text("Remove from Library")
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .transition(.opacity)
                        } else {
                            LazyVStack {
                                ForEach(manga.filter {
                                    search(
                                        needle: searchText.lowercased(),
                                        haystack: $0.title?.lowercased() ?? ""
                                    )
                                }, id: \.self) { m in
                                    Button {
                                        if let c = getNextChapter(for: m) {
                                            selectedChapter = ChapterWithManga(
                                                chapter: c,
                                                manga: m
                                            )
                                        } else {
                                            selectedManga = m
                                            openMangaInfoView = true
                                        }
                                    } label: {
                                        LibraryListCell(manga: m) {
                                            if let chapterNum = getNextChapter(for: m)?.chapterNum {
                                                Text("Chapter \(chapterNum, specifier: "%g")")
                                                    .foregroundColor(.secondaryLabel)
                                                    .font(.system(size: 13))
                                                    .lineLimit(1)
                                                    .padding(.top, 8)
                                            }
                                        } menuContent: {
                                            Button {
                                                selectedManga = m
                                                openMangaInfoView = true
                                            } label: {
                                                Label("Manga Info", systemImage: "info.circle")
                                            }
                                            Button {
                                                DataManager.shared.delete(manga: m)
                                                loadManga()
                                            } label: {
                                                Label("Remove from Library", systemImage: "trash")
                                            }
                                        }
                                        .transition(.move(edge: .top))
                                    }
                                    .contextMenu {
                                        Button {
                                            selectedManga = m
                                            openMangaInfoView = true
                                        } label: {
                                            Label("Manga Info", systemImage: "info.circle")
                                        }
                                        Button {
                                            DataManager.shared.delete(manga: m)
                                            loadManga()
                                        } label: {
                                            Label("Remove from Library", systemImage: "trash")
                                        }
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .background {
                        NavigationLink(isActive: $openMangaInfoView) {
                            if let m = selectedManga {
                                MangaView(manga: m)
                                    .onDisappear {
                                        DataManager.shared.loadLibrary()
                                        loadManga()
                                        Task {
                                            await loadHistory()
                                        }
                                    }
                            } else {
                                EmptyView()
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                }
                    .navigationTitle("Library")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationSearchBar {
                        SearchBar("Search", text: $searchText, isEditing: $isEditing)
                            .showsCancelButton(isEditing)
                    }
                    .toolbar {
                        Button {
                            showingSettings.toggle()
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(presented: $showingSettings)
        }
        .fullScreenCover(item: $selectedChapter, onDismiss: {
            Task {
                await loadHistory()
            }
        }, content: { item in
            ReaderView(manga: item.manga, chapter: item.chapter, startPage: DataManager.shared.currentPage(manga: item.manga, chapterId: item.chapter.id))
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    if let value = selectedChapter {
                        DataManager.shared.setOpened(manga: value.manga)
                        loadManga()
                    }
                }
        })
        .onChange(of: sortMethod) { _ in
            loadManga()
        }
        .onAppear {
            loadManga()
            Task {
                await loadHistory()
                if !updatedLibrary {
                    await DataManager.shared.getLatestMangaDetails()
                    await DataManager.shared.updateLibrary()
                    loadManga()
                    updatedLibrary = true
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func getNextChapter(for manga: Manga) -> Chapter? {
        let mangaChapters = chapters[manga.id]
        return mangaChapters?.last(where: { readHistory[manga.id]?[$0.id] ?? false }) ?? mangaChapters?.first
    }
    
    func loadManga() {
        var loadedManga = DataManager.shared.manga
        if sortMethod == 1 {
            loadedManga.sort {
                $0.title ?? "" < $1.title ?? ""
            }
        } else if sortMethod == 2 {
            loadedManga.sort {
                $0.author ?? "" < $1.author ?? ""
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            self.manga = loadedManga
        }
    }
    
    func loadHistory() async {
        for m in manga {
            readHistory[m.id] = DataManager.shared.getReadHistory(manga: m)
            chapters[m.id] = (try? await SourceManager.shared.source(for: m.provider)?.getChapterList(manga: m)) ?? []
        }
    }
    
    func search(needle: String, haystack: String) -> Bool {
        guard needle.count <= haystack.count else {
            return false
        }
      
        if needle == haystack {
            return true
        }
      
        var needleIdx = needle.startIndex
        var haystackIdx = haystack.startIndex
      
        while needleIdx != needle.endIndex {
            if haystackIdx == haystack.endIndex {
                return false
            }
            if needle[needleIdx] == haystack[haystackIdx] {
                needleIdx = needle.index(after: needleIdx)
            }
            haystackIdx = haystack.index(after: haystackIdx)
        }
        return true
    }
}
