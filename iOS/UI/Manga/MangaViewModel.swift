//
//  MangaViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import Foundation

@MainActor
class MangaViewModel {

    var chapterList: [Chapter] {
        filteredChapterList
    }
    var fullChapterList: [Chapter] = []
    private var filteredChapterList: [Chapter] = []
    var readingHistory: [String: (page: Int, date: Int)] = [:] // chapterId: (page, date)
    var downloadProgress: [String: Float] = [:] // chapterId: progress

    var sortMethod: ChapterSortOption = .sourceOrder
    var sortAscending: Bool = false
    var filters: [ChapterFilterOption] = []
    var langFilter: String?
    var scanlatorFilter: [String] = []

    var savedScanlatorList: [String]?

    var hasUnreadFilter: Bool {
        filters.contains(where: { $0.type == .unread })
    }
    var hasDownloadFilter: Bool {
        filters.contains(where: { $0.type == .downloaded })
    }

    func loadChapterList(manga: Manga) async {
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id, context: context)
        }

        if inLibrary {
            // load from db
            fullChapterList = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getChapters(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ).map {
                    $0.toChapter()
                }
            }
        } else {
            // load from source
            guard let source = SourceManager.shared.source(for: manga.sourceId) else { return }
            fullChapterList = (try? await source.getChapterList(manga: manga)) ?? []
        }

        filterChapterList()
    }

    func loadHistory(manga: Manga) async {
        readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceId, mangaId: manga.id)
    }

    func removeHistory(for chapters: [Chapter]) {
        for chapter in chapters {
            readingHistory.removeValue(forKey: chapter.id)
        }
        // update chapter list if we filter unread chapters
        if hasUnreadFilter {
            filterChapterList()
            NotificationCenter.default.post(name: NSNotification.Name("reloadChapterList"), object: nil)
        }
    }

    func addHistory(for chapters: [Chapter], date: Date = Date()) {
        for chapter in chapters {
            readingHistory[chapter.id] = (-1, Int(date.timeIntervalSince1970))
        }
        // update chapter list if we filter unread chapters
        if hasUnreadFilter {
            filterChapterList()
            NotificationCenter.default.post(name: NSNotification.Name("reloadChapterList"), object: nil)
        }
    }

    func sortChapters(method: ChapterSortOption? = nil, ascending: Bool? = nil) {
        let method = method ?? sortMethod
        let ascending = ascending ?? sortAscending
        sortMethod = method
        sortAscending = ascending
        switch method {
        case .sourceOrder:
            if ascending {
                filteredChapterList.sort { $0.sourceOrder > $1.sourceOrder }
            } else {
                filteredChapterList.sort { $0.sourceOrder < $1.sourceOrder }
            }
        case .chapter:
            if ascending {
                filteredChapterList.sort { $0.chapterNum ?? 0 > $1.chapterNum ?? 0 }
            } else {
                filteredChapterList.sort { $0.chapterNum ?? 0 < $1.chapterNum ?? 0 }
            }
        case .uploadDate:
            let now = Date()
            if ascending {
                filteredChapterList.sort { $0.dateUploaded ?? now > $1.dateUploaded ?? now }
            } else {
                filteredChapterList.sort { $0.dateUploaded ?? now < $1.dateUploaded ?? now }
            }
        }
    }

    func filterChapterList() {
        filteredChapterList = fullChapterList
        sortChapters(method: sortMethod, ascending: sortAscending)

        // filter by language and scanlators
        if langFilter != nil || !scanlatorFilter.isEmpty {
            filteredChapterList = filteredChapterList.filter {
                let cond1 = if let langFilter {
                    $0.lang == langFilter
                } else {
                    true
                }
                let cond2 = if !scanlatorFilter.isEmpty  {
                    scanlatorFilter.contains($0.scanlator ?? "")
                } else {
                    true
                }
                return cond1 && cond2
            }
        }

        for filter in filters {
            switch filter.type {
            case .downloaded:
                filteredChapterList = filteredChapterList.filter {
                    let downloaded = !DownloadManager.shared.isChapterDownloaded(chapter: $0)
                    return filter.exclude ? downloaded : !downloaded
                }
            case .unread:
                self.filteredChapterList = self.filteredChapterList.filter {
                    let isCompleted = self.readingHistory[$0.id]?.0 == -1
                    return filter.exclude ? isCompleted : !isCompleted
                }
            }
        }
    }

    func languageFilterChanged(_ newValue: String?, manga: Manga) async {
        langFilter = newValue
        filterChapterList()
        await saveFilters(manga: manga)
        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
    }

    func scanlatorFilterChanged(_ newValue: [String], manga: Manga) async {
        scanlatorFilter = newValue
        filterChapterList()
        await saveFilters(manga: manga)
        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
    }

    func generageChapterFlags() -> Int {
        var flags: Int = 0
        if sortAscending {
            flags |= ChapterFlagMask.sortAscending
        }
        flags |= sortMethod.rawValue << 1
        for filter in filters {
            switch filter.type {
            case .downloaded:
                flags |= ChapterFlagMask.downloadFilterEnabled
                if filter.exclude {
                    flags |= ChapterFlagMask.downloadFilterExcluded
                }
            case .unread:
                flags |= ChapterFlagMask.unreadFilterEnabled
                if filter.exclude {
                    flags |= ChapterFlagMask.unreadFilterExcluded
                }
            }
        }
        return flags
    }

    func saveFilters(manga: Manga) async {
        manga.chapterFlags = generageChapterFlags()
        manga.langFilter = langFilter
        manga.scanlatorFilter = scanlatorFilter
        await CoreDataManager.shared.updateMangaDetails(manga: manga)
    }

    func getSourceDefaultLanguages(sourceId: String) -> [String] {
        guard let source = SourceManager.shared.source(for: sourceId) else { return [] }
        return source.getDefaultLanguages()
    }

    func getScanlators() -> [String] {
        if let savedScanlatorList {
            return savedScanlatorList
        }
        guard !fullChapterList.isEmpty else {
            return []
        }
        var scanlators: Set<String> = []
        for chapter in fullChapterList {
            scanlators.insert(chapter.scanlator ?? "")
        }
        let result = scanlators.sorted()
        savedScanlatorList = result
        return result
    }

    enum ChapterResult {
        case none
        case allRead
        case chapter(Chapter)
    }

    // returns first chapter not completed, or falls back to top chapter
    func getNextChapter() -> ChapterResult {
        guard !filteredChapterList.isEmpty else { return .none }
        // get first chapter not completed
        let chapter = getOrderedChapterList().reversed().first(where: { readingHistory[$0.id]?.page ?? 0 != -1 })
        if let chapter = chapter {
            return .chapter(chapter)
        }
        // get last read chapter (doesn't work if all chapters were marked read at the same time)
//        let id = viewModel.readingHistory.max { a, b in a.value.date < b.value.date }?.key
//        let lastRead: Chapter
//        if let id = id, let match = viewModel.filteredChapterList.first(where: { $0.id == id }) {
//            lastRead = match
//        } else {
//            lastRead = viewModel.filteredChapterList.last!
//        }
        return .allRead
    }

    func getOrderedChapterList() -> [Chapter] {
        (sortAscending && sortMethod == .sourceOrder) || (!sortAscending && sortMethod != .sourceOrder)
            ? filteredChapterList.reversed()
            : filteredChapterList
    }
}
