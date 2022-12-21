//
//  BookManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import CoreData

class BookManager {

    static let shared = BookManager()
}

// MARK: - Library Updating
extension BookManager {

    /// Check if a book should skip updating based on skip options.
    @MainActor
    private func shouldSkip(book: Book, options: [String], context: NSManagedObjectContext? = nil) -> Bool {
        // completed
        if options.contains("completed") && book.status == .completed {
            return true
        }
        // has unread chapters
        if options.contains("hasUnread") && CoreDataManager.shared.unreadCount(
            sourceId: book.sourceId,
            mangaId: book.id,
            context: context
        ) > 0 {
            return true
        }
        // has no read chapters
        if options.contains("notStarted") && CoreDataManager.shared.readCount(
            sourceId: book.sourceId,
            mangaId: book.id,
            context: context
        ) == 0 {
            return true
        }

        return false
    }

    /// Get the latest chapters for all books in the array, indexed by book.key.
    private func getLatestChapters(books: [Book], skipOptions: [String] = []) async -> [String: [Chapter]] {
        await withTaskGroup(
            of: (String, [Chapter]).self,
            returning: [String: [Chapter]].self,
            body: { taskGroup in
                for book in books {
                    if await shouldSkip(book: book, options: skipOptions) {
                        continue
                    }
                    taskGroup.addTask {
                        let chapters = try? await SourceManager.shared.source(for: book.sourceId)?
                            .getChapterList(manga: book.toManga())
                        return (book.key, chapters ?? [])
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
    func updateBookDetails(books: [Book]) async {
        for book in books {
            guard
                let newInfo = try? await SourceManager.shared.source(for: book.sourceId)?.getMangaDetails(manga: book.toManga())
            else { continue }
            book.load(from: newInfo)
        }
    }

    /// Refresh manga objects in library.
    @MainActor
    func refreshLibrary(forceAll: Bool = false) async {
        let allBooks = CoreDataManager.shared.getLibraryManga()
            .compactMap { $0.manga?.toBook() }

        // check if connected to wi-fi
        if UserDefaults.standard.bool(forKey: "Library.updateOnlyOnWifi") && Reachability.getConnectionType() != .wifi {
            return
        }

        // fetch new details
        if forceAll || UserDefaults.standard.bool(forKey: "Library.refreshMetadata") {
            await updateBookDetails(books: allBooks)
        }

        let skipOptions = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.skipTitles") ?? []
        let excludedCategories = forceAll ? [] : UserDefaults.standard.stringArray(forKey: "Library.excludedUpdateCategories") ?? []

        // fetch new chapters
        let newChapters = await getLatestChapters(books: allBooks, skipOptions: skipOptions)

        await CoreDataManager.shared.container.performBackgroundTask { context in
            for book in allBooks {
                guard let chapters = newChapters[book.key] else { continue }

                guard let libraryObject = CoreDataManager.shared.getLibraryManga(
                    sourceId: book.sourceId,
                    mangaId: book.id,
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

                // update manga object
                if let mangaObject = libraryObject.manga {
                    // update details
                    mangaObject.load(from: book)

                    // update chapter list
                    if mangaObject.chapters?.count != chapters.count && !chapters.isEmpty {
                        CoreDataManager.shared.setChapters(
                            chapters,
                            sourceId: book.sourceId,
                            mangaId: book.id,
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
