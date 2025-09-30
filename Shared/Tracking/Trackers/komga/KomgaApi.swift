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

    func getState(sourceKey: String, mangaKey: String, url: String) async throws -> TrackState? {
        guard let url = URL(string: "\(url)/read-progress/tachiyomi")
        else { return nil }

        let helper = KomgaHelper(sourceKey: sourceKey)
        guard let auth = helper.getAuthorizationHeader() else {
            throw KomgaTrackerError.notLoggedIn
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: KomgaReadProgress = try await URLSession.shared.object(from: request)
        let useChapters = shouldUseChapters(sourceKey: sourceKey, mangaKey: mangaKey)

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

    func update(sourceKey: String, mangaKey: String, url: String, update: TrackUpdate) async throws {
        let useChapters = shouldUseChapters(sourceKey: sourceKey, mangaKey: mangaKey)
        guard
            let lastReadVolume = useChapters ? update.lastReadChapter.flatMap({ Int(floor($0)) }) : update.lastReadVolume,
            let url = URL(string: "\(url)/read-progress/tachiyomi")
        else { return }

        let helper = KomgaHelper(sourceKey: sourceKey)
        guard let auth = helper.getAuthorizationHeader() else {
            throw KomgaTrackerError.notLoggedIn
        }

        var request = URLRequest(url: url)
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "PUT"

        request.httpBody = try? JSONEncoder().encode(KomgaReadProgressUpdate(lastBookNumberSortRead: Float(lastReadVolume)))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await URLSession.shared.data(for: request)
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
