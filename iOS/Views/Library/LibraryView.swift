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
    @Binding var ascending: Bool
    
    let options: [String]
    
    var body: some View {
        Menu {
            ForEach(0..<options.count) { i in
                Button {
                    if selection == i {
                        ascending.toggle()
                    } else {
                        ascending = false
                    }
                    selection = i
                } label: {
                    if i == selection {
                        Label(options[i], systemImage: ascending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(options[i])
                    }
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
    @AppStorage("librarySortAscending") var sortAscending = false
    
    @State var manga: [Manga] = []
    @State var chapters: [String: [Chapter]] = [:]
    @State var readHistory: [String: [String: Int]] = [:]
    
    @State var showingSettings: Bool = false
    @State var isEditing: Bool = false
    @State var searchText: String = ""
    
    @State var selectedChapter: ChapterWithManga?
    @State var selectedManga: Manga? = nil
    @State var openMangaInfoView: Bool = false
    
    @State var updatedLibrary: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
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
                    .sheet(isPresented: $showingSettings) {
                        SettingsView(presented: $showingSettings)
                    }
                } else {
                    ScrollView {
                        VStack {
                            HStack {
                                Text("Sort")
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, -2)
                                DropMenu(selection: $sortMethod, ascending: $sortAscending, options: [
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
                                        .padding(8)
                                        .background(grid ? .clear : .secondaryFill)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 0)
                            
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
                                        .onAppear {
                                            selectedChapter = nil
                                        }
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
                    .sheet(isPresented: $showingSettings) {
                        SettingsView(presented: $showingSettings)
                    }
                    .fullScreenCover(item: $selectedChapter, onDismiss: {
                        selectedChapter = nil
                        Task {
                            await loadHistory()
                        }
                    }, content: { item in
                        ReaderView(manga: item.manga, chapter: item.chapter, chapterList: chapters[item.manga.id] ?? [])
                            .edgesIgnoringSafeArea(.all)
                            .onAppear {
                                if let value = selectedChapter {
                                    DataManager.shared.setOpened(manga: value.manga)
                                    loadManga()
                                }
                            }
                    })
                    // Necessary to fix iOS 14 SwiftUI bug
                    EmptyView()
                        .sheet(isPresented: $showingSettings) {
                            SettingsView(presented: $showingSettings)
                        }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Find in Library", text: $searchText, isEditing: $isEditing)
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
        .onChange(of: sortMethod) { _ in
            loadManga()
        }
        .onChange(of: sortAscending) { _ in
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
        let id = readHistory[manga.id]?.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters[manga.id]?.first { $0.id == id }
        }
        return chapters[manga.id]?.first
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
        if sortAscending {
            loadedManga.reverse()
        }
        // animation doesn't work pre-ios 15 due to some swiftui bug I don't care to figure out
        if #available(iOS 15.0, *) {
            withAnimation {
                manga = loadedManga
            }
        } else {
            manga = loadedManga
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
