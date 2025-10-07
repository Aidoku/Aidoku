//
//  KomgaApi.swift
//  Aidoku
//
//  Created by Skitty on 9/16/25.
//

import Foundation

class KomgaApi {
    private func shouldUseChapters(sourceKey: String, mangaKey: String) -> Bool {
        let uniqueKey = "\(sourceKey).\(mangaKey)"
        let key = "Manga.chapterDisplayMode.\(uniqueKey)"
        let displayMode = ChapterTitleDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default

        if displayMode == .chapter {
            return true
        } else if displayMode == .volume {
            return false
        } else {
            return UserDefaults.standard.bool(forKey: "\(sourceKey).useChapters")
        }
    }

    func getState(sourceKey: String, seriesId: String) async throws -> TrackState? {
        let helper = KomgaHelper(sourceKey: sourceKey)

        guard let auth = helper.getAuthorizationHeader() else {
            throw KomgaTrackerError.notLoggedIn
        }

        let url = try helper.getServerUrl(path: "/api/v2/series/\(seriesId)/read-progress/tachiyomi")

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: KomgaReadProgress = try await URLSession.shared.object(from: request)
        let useChapters = shouldUseChapters(sourceKey: sourceKey, mangaKey: seriesId)

        if useChapters {
            return .init(
                lastReadChapter: data.lastReadContinuousNumberSort,
                totalChapters: Int(floor(data.maxNumberSort)),
            )
        } else {
            return .init(
                lastReadVolume: Int(floor(data.lastReadContinuousNumberSort)),
                totalVolumes: Int(floor(data.maxNumberSort)),
            )
        }
    }

    func update(sourceKey: String, seriesId: String, update: TrackUpdate) async throws {
        let useChapters = shouldUseChapters(sourceKey: sourceKey, mangaKey: seriesId)
        guard let lastReadVolume = useChapters ? update.lastReadChapter.flatMap({ Int(floor($0)) }) : update.lastReadVolume
        else { return }

        let helper = KomgaHelper(sourceKey: sourceKey)
        guard let auth = helper.getAuthorizationHeader() else {
            throw KomgaTrackerError.notLoggedIn
        }

        let url = try helper.getServerUrl(path: "/api/v2/series/\(seriesId)/read-progress/tachiyomi")

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "PUT"

        request.httpBody = try? JSONEncoder().encode(KomgaReadProgressUpdate(lastBookNumberSortRead: Float(lastReadVolume)))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await URLSession.shared.data(for: request)
    }

    func updateReadProgress(
        sourceKey: String,
        bookId: String,
        progress: ChapterReadProgress
    ) async throws {
        let helper = KomgaHelper(sourceKey: sourceKey)
        let bookUrl = try helper.getServerUrl(path: "/api/v1/books/\(bookId)")

        guard let url = URL(string: "\(bookUrl)/read-progress") else { return }

        guard let auth = helper.getAuthorizationHeader() else {
            throw KomgaTrackerError.notLoggedIn
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if !progress.completed && progress.page <= 0 {
            // mark book as unread: https://komga.org/docs/openapi/delete-book-read-progress
            request.httpMethod = "DELETE"
        } else {
            // mark book read progress: https://komga.org/docs/openapi/mark-book-read-progress
            request.httpMethod = "PATCH"

            let page = try await {
                if progress.completed {
                    // if marking completed, we need to set the page to the total pages
                    let book: KomgaBook = try await helper.request(path: "/api/v1/books/\(bookId)")
                    return book.media.pagesCount
                } else {
                    return progress.page
                }
            }()

            request.httpBody = try? JSONEncoder().encode(KomgaBookReadProgressUpdate(
                page: page,
                completed: progress.completed
            ))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        _ = try await URLSession.shared.data(for: request)
    }

    func getSeriesReadProgress(sourceKey: String, seriesId: String) async throws -> [String: ChapterReadProgress] {
        let helper = KomgaHelper(sourceKey: sourceKey)
        let response: KomgaPageResponse<[KomgaBook]> = try await helper.request(path: "/api/v1/series/\(seriesId)/books?unpaged=true")

        var progressMap: [String: ChapterReadProgress] = [:]

        for book in response.content {
            guard let readProgress = book.readProgress else {
                continue
            }
            progressMap[book.id] = .init(
                completed: readProgress.completed,
                page: readProgress.page,
                date: readProgress.lastModified
            )
        }

        return progressMap
    }
}

// MARK: - Models

private struct KomgaReadProgress: Codable {
    let booksCount: Int?
    let booksReadCount: Int?
    let booksUnreadCount: Int?
    let booksInProgressCount: Int?
    let lastReadContinuousNumberSort: Float
    let maxNumberSort: Float
}

private struct KomgaReadProgressUpdate: Codable {
    let lastBookNumberSortRead: Float
}

private struct KomgaBookReadProgressUpdate: Codable {
    let page: Int
    let completed: Bool
}
