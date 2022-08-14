//
//  LibraryViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/25/22.
//

import Foundation
import CoreData

class LibraryViewModel {

    var books: [BookInfo] = []
    var pinnedBooks: [BookInfo] = []

    // temporary storage when searching
    var storedBooks: [BookInfo]?
    var storedPinnedBooks: [BookInfo]?

    enum PinType {
        case none
        case unread
        case updated
    }

    enum SortMethod: Int {
        case alphabetical = 0
        case lastRead
        case lastOpened
        case lastUpdated
        case dateAdded
        case unreadChapters // ?
        case totalChapters

        func toSortString() -> String {
            switch self {
            case .alphabetical: return "manga.title"
            case .lastRead: return "lastRead"
            case .lastOpened: return "lastOpened"
            case .lastUpdated: return "lastUpdated"
            case .dateAdded: return "dateAdded"
            case .unreadChapters: return ""
            case .totalChapters: return "manga.chapterCount"
            }
        }
    }

    var pinType: PinType = .updated
    lazy var sortMethod = SortMethod(rawValue: UserDefaults.standard.integer(forKey: "Library.sortOption")) ?? .lastOpened
    lazy var sortAscending = UserDefaults.standard.bool(forKey: "Library.sortAscending")

    lazy var categories = CoreDataManager.shared.getCategories().map { $0.title ?? "" }
    var currentCategory: String?
    var categoryLocked: Bool {
        guard UserDefaults.standard.bool(forKey: "Library.lockLibrary") else { return false }
        if let currentCategory = currentCategory {
            return UserDefaults.standard.stringArray(forKey: "Library.lockedCategories")?.contains(currentCategory) ?? false
        }
        return true
    }

    func refreshCategories() {
        categories = CoreDataManager.shared.getCategories().map { $0.title ?? "" }
        if currentCategory != nil && !categories.contains(currentCategory!) {
            currentCategory = nil
            loadLibrary()
        }
    }

    func loadLibrary() {
        pinnedBooks = []
        books = []

        let request = LibraryMangaObject.fetchRequest()
        if let currentCategory = currentCategory {
            request.predicate = NSPredicate(format: "manga != nil AND ANY categories.title == %@", currentCategory)
        } else {
            request.predicate = NSPredicate(format: "manga != nil")
        }
        if sortMethod != .unreadChapters {
            request.sortDescriptors = [
                NSSortDescriptor(
                    key: sortMethod.toSortString(),
                    ascending: sortMethod == .alphabetical ? !sortAscending : sortAscending
                )
            ]
        }
        guard let libraryObjects = try? CoreDataManager.shared.context.fetch(request) else {
            return
        }

        for object in libraryObjects {
            let manga = object.manga!

            let unreadCount = CoreDataManager.shared.unreadCount(
                sourceId: manga.sourceId,
                mangaId: manga.id
            )

            let info = BookInfo(
                bookId: manga.id,
                sourceId: manga.sourceId,
                coverUrl: manga.cover != nil ? URL(string: manga.cover!) : nil,
                title: manga.title,
                author: manga.author,
                url: manga.url != nil ? URL(string: manga.url!) : nil,
                unread: unreadCount
            )

            switch pinType {
            case .none:
                books.append(info)
            case .unread:
                if info.unread > 0 {
                    pinnedBooks.append(info)
                } else {
                    books.append(info)
                }
            case .updated:
                if object.lastUpdated > object.lastOpened {
                    pinnedBooks.append(info)
                } else {
                    books.append(info)
                }
            }
        }

        if sortMethod == .unreadChapters {
            if sortAscending {
                pinnedBooks.sort(by: { $0.unread < $1.unread })
                books.sort(by: { $0.unread < $1.unread })
            } else {
                pinnedBooks.sort(by: { $0.unread > $1.unread })
                books.sort(by: { $0.unread > $1.unread })
            }
        }
    }

    func fetchUnreads() {
        for (i, book) in books.enumerated() {
            books[i].unread = CoreDataManager.shared.unreadCount(
                sourceId: book.sourceId,
                mangaId: book.bookId
            )
        }
        for (i, book) in pinnedBooks.enumerated() {
            pinnedBooks[i].unread = CoreDataManager.shared.unreadCount(
                sourceId: book.sourceId,
                mangaId: book.bookId
            )
        }
    }

    func sortLibrary() {
        switch sortMethod {
        case .alphabetical:
            if sortAscending {
                pinnedBooks.sort(by: { $0.title ?? "" > $1.title ?? "" })
                books.sort(by: { $0.title ?? "" > $1.title ?? "" })
            } else {
                pinnedBooks.sort(by: { $0.title ?? "" < $1.title ?? "" })
                books.sort(by: { $0.title ?? "" < $1.title ?? "" })
            }

        case .unreadChapters:
            if sortAscending {
                pinnedBooks.sort(by: { $0.unread < $1.unread })
                books.sort(by: { $0.unread < $1.unread })
            } else {
                pinnedBooks.sort(by: { $0.unread > $1.unread })
                books.sort(by: { $0.unread > $1.unread })
            }

        default:
            loadLibrary()
        }
    }

    func toggleSort(method: SortMethod) {
        if sortMethod == method {
            sortAscending.toggle()
        } else {
            sortMethod = method
            sortAscending = false
            UserDefaults.standard.set(sortMethod.rawValue, forKey: "Library.sortOption")
        }

        UserDefaults.standard.set(sortAscending, forKey: "Library.sortAscending")

        sortLibrary()
    }

    func search(query: String) {
        guard !query.isEmpty else {
            if let storedBooks = storedBooks {
                books = storedBooks
                self.storedBooks = nil
            }
            if let storedPinnedBooks = storedPinnedBooks {
                pinnedBooks = storedPinnedBooks
                self.storedPinnedBooks = nil
            }
            return
        }
        if storedBooks == nil {
            storedBooks = books
            storedPinnedBooks = pinnedBooks
        }
        guard let storedBooks = storedBooks, let storedPinnedBooks = storedPinnedBooks else {
            return
        }

        let query = query.lowercased()
        pinnedBooks = storedPinnedBooks.filter { $0.title?.lowercased().contains(query) ?? false }
        books = storedBooks.filter { $0.title?.lowercased().contains(query) ?? false }
    }

    func bookOpened(sourceId: String, bookId: String) {
        guard sortMethod == .lastOpened || pinType == .updated else { return }

        let pinnedIndex = self.pinnedBooks.firstIndex(where: { $0.bookId == bookId && $0.sourceId == sourceId })
        if let pinnedIndex = pinnedIndex {
            let book = self.pinnedBooks.remove(at: pinnedIndex)
            self.books.insert(book, at: 0)
        } else {
            let index = self.books.firstIndex(where: { $0.bookId == bookId && $0.sourceId == sourceId })
            if let index = index {
                let book = self.books.remove(at: index)
                self.books.insert(book, at: 0)
            }
        }
    }

    func removeFromLibrary(book: BookInfo) {
        pinnedBooks.removeAll { $0.sourceId == book.sourceId && book.bookId == $0.bookId }
        books.removeAll { $0.sourceId == book.sourceId && book.bookId == $0.bookId }

        CoreDataManager.shared.removeManga(sourceId: book.sourceId, id: book.bookId)
    }
}

// MARK: - Library Updating
extension LibraryViewModel {

    /// Check if a manga should skip updating based on skip options.
    private func shouldSkip(manga: Manga, options: [String], context: NSManagedObjectContext? = nil) -> Bool {
        // manga completed
        if options.contains("completed") && manga.status == .completed {
            return true
        }
        // manga has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            context: context
        ) > 0 {
            return true
        }
        // manga has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: manga.sourceId,
            mangaId: manga.id,
            context: context
        ) == 0 {
            return true
        }

        return false
    }

    /// Get the latest chapters for all manga in the array, indexed by manga.key.
    private func getLatestChapters(manga: [Manga], skipOptions: [String] = []) async -> [String: [Chapter]] {
        await withTaskGroup(
            of: (String, [Chapter]).self,
            returning: [String: [Chapter]].self,
            body: { taskGroup in
                let backgroundContext = CoreDataManager.shared.container.newBackgroundContext()
                for manga in manga {
                    if shouldSkip(manga: manga, options: skipOptions, context: backgroundContext) {
                        continue
                    }
                    taskGroup.addTask {
                        let chapters = try? await SourceManager.shared.source(for: manga.sourceId)?.getChapterList(manga: manga)
                        return (manga.key, chapters ?? [])
                    }
                }

                var results: [String: [Chapter]] = [:]
                for await result in taskGroup {
                    results[result.0] = result.1
                }
                return results
            }
        )
    }

    /// Update properties on manga from latest source info.
    func updateMangaDetails(manga: [Manga]) async {
        for manga in manga {
            guard let newInfo = try? await SourceManager.shared.source(for: manga.sourceId)?.getMangaDetails(manga: manga) else {
                continue
            }
            manga.load(from: newInfo)
        }
    }

    /// Refresh manga objects in library.
    func refreshLibrary() async {
        let allManga = CoreDataManager.shared.getLibraryManga()
            .compactMap { $0.manga?.toManga() }

        // check if connected to wi-fi
        if UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi") && Reachability.getConnectionType() != .wifi {
            return
        }

        // fetch new manga details
        if UserDefaults.standard.bool(forKey: "Library.refreshMetadata") {
            await updateMangaDetails(manga: allManga)
        }

        let skipOptions = UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? []

        // fetch new chapters
        let newChapters = await getLatestChapters(manga: allManga, skipOptions: skipOptions)

        await CoreDataManager.shared.container.performBackgroundTask { context in
            for manga in allManga {
                guard let chapters = newChapters[manga.key] else { continue }

                guard let libraryObject = CoreDataManager.shared.getLibraryManga(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ) else {
                    continue
                }

                // check if excluded via category
                let categories = CoreDataManager.shared.getCategories(
                    libraryManga: libraryObject
                ).compactMap { $0.title }

                if !categories.isEmpty {
                    if excludedCategories.contains(where: categories.contains) {
                        continue
                    }
                }

                // update manga
                if let mangaObject = libraryObject.manga {
                    // update details
                    mangaObject.load(from: manga)

                    // update chapter list
                    if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                        CoreDataManager.shared.setChapters(
                            chapters,
                            sourceId: manga.sourceId,
                            mangaId: manga.id,
                            context: context
                        )
                        libraryObject.lastUpdated = Date()
                    }
                }
            }

            // save changes (runs on main thread)
            if context.hasChanges {
                try? context.save()
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "Library.lastUpdated")
        }
    }
}
