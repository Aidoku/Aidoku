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

    struct LibraryFilter {
        var type: FilterMethod
        var exclude: Bool
    }

    enum FilterMethod: Int {
        case downloaded = 0
    }

    lazy var pinType: PinType = getPinType()
    lazy var sortMethod = SortMethod(rawValue: UserDefaults.standard.integer(forKey: "Library.sortOption")) ?? .lastOpened
    lazy var sortAscending = UserDefaults.standard.bool(forKey: "Library.sortAscending")

    var filters: [LibraryFilter] = []

    lazy var categories = CoreDataManager.shared.getCategories().map { $0.title ?? "" }
    lazy var currentCategory: String? = UserDefaults.standard.string(forKey: "Library.currentCategory") {
        didSet {
            UserDefaults.standard.set(currentCategory, forKey: "Library.currentCategory")
        }
    }
    var categoryLocked: Bool {
        guard UserDefaults.standard.bool(forKey: "Library.lockLibrary") else { return false }
        if let currentCategory = currentCategory {
            return UserDefaults.standard.stringArray(forKey: "Library.lockedCategories")?.contains(currentCategory) ?? false
        }
        return true
    }

    func getPinType() -> PinType {
        if UserDefaults.standard.bool(forKey: "Library.pinManga") {
            switch UserDefaults.standard.integer(forKey: "Library.pinMangaType") {
            case 0: return .unread
            case 1: return .updated
            default: return .none
            }
        } else {
            return .none
        }
    }

    func refreshCategories() {
        categories = CoreDataManager.shared.getCategories().map { $0.title ?? "" }
        if currentCategory != nil && !categories.contains(currentCategory!) {
            currentCategory = nil
            loadLibrary()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
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

        main: for object in libraryObjects {
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

            // process filters
            for filter in filters {
                switch filter.type {
                case .downloaded:
                    let downloaded = DownloadManager.shared.hasDownloadedChapter(sourceId: info.sourceId, mangaId: info.bookId)
                    let shouldSkip = filter.exclude ? downloaded : !downloaded
                    if shouldSkip {
                        continue main
                    }
                }
            }

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
            sortLibrary()
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
        if sortMethod == .unreadChapters {
            sortLibrary()
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

    func toggleFilter(method: FilterMethod) {
        let filterIndex = filters.firstIndex(where: { $0.type == method })
        if let filterIndex = filterIndex {
            if filters[filterIndex].exclude {
                filters.remove(at: filterIndex)
            } else {
                filters[filterIndex].exclude = true
            }
        } else {
            filters.append(LibraryFilter(type: method, exclude: false))
        }

        loadLibrary()
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

        let pinnedIndex = pinnedBooks.firstIndex(where: { $0.bookId == bookId && $0.sourceId == sourceId })
        if let pinnedIndex = pinnedIndex {
            if sortMethod == .lastOpened {
                let book = pinnedBooks.remove(at: pinnedIndex)
                books.insert(book, at: 0)
            } else {
                loadLibrary() // don't know where to put in books array, just refresh
            }
        } else if sortMethod == .lastOpened {
            let index = books.firstIndex(where: { $0.bookId == bookId && $0.sourceId == sourceId })
            if let index = index {
                let book = books.remove(at: index)
                books.insert(book, at: 0)
            }
        }
    }

    func removeFromLibrary(book: BookInfo) {
        pinnedBooks.removeAll { $0 == book }
        books.removeAll { $0 == book }
        Task {
            await CoreDataManager.shared.removeManga(sourceId: book.sourceId, id: book.bookId)
        }
    }

    func removeFromCurrentCategory(book: BookInfo) {
        guard let currentCategory = currentCategory else { return }
        pinnedBooks.removeAll { $0 == book }
        books.removeAll { $0 == book }
        Task {
            await CoreDataManager.shared.removeCategoriesFromManga(
                sourceId: book.sourceId,
                mangaId: book.bookId,
                categories: [currentCategory]
            )
        }
    }

    func shouldUpdateLibrary() -> Bool {
        let lastUpdated = UserDefaults.standard.double(forKey: "Library.lastUpdated")
        let interval: Double = [
            "never": Double(-1),
            "12hours": 43200,
            "daily": 86400,
            "2days": 172800,
            "weekly": 604800
        ][UserDefaults.standard.string(forKey: "Library.updateInterval")] ?? Double(0)
        guard interval > 0 else { return false }
        if Date().timeIntervalSince1970 - lastUpdated > interval {
            return true
        }
        return false
    }
}
