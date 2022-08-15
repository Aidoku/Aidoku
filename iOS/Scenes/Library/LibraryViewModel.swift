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
