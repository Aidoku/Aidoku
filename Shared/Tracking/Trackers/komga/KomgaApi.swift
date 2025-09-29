//
//  KomgaApi.swift
//  Aidoku
//
//  Created by Skitty on 9/16/25.
//

import Foundation

class KomgaApi {
    func getState(sourceKey: String, url: String, mangaId: String? = nil) async throws -> TrackState? {
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

        // Check for display mode
        let uniqueKey = "\(sourceKey).\(mangaId ?? "")"
        let key = "Manga.chapterDisplayMode.\(uniqueKey)"
        let displayMode = MangaDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default
        let mangaVolumeMode = displayMode == .volume
        let mangaChapterMode = displayMode == .chapter

        let useChapters: Bool
        if mangaChapterMode {
            useChapters = true
        } else if mangaVolumeMode {
            useChapters = false
        } else {
            useChapters = UserDefaults.standard.bool(forKey: "\(sourceKey).useChapters")
        }

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

    func update(sourceKey: String, url: String, update: TrackUpdate, mangaId: String? = nil) async throws {
        // Check for display mode
        let uniqueKey = "\(sourceKey).\(mangaId ?? "")"
        let key = "Manga.chapterDisplayMode.\(uniqueKey)"
        let displayMode = MangaDisplayMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default
        let mangaVolumeMode = displayMode == .volume
        let mangaChapterMode = displayMode == .chapter

        let useChapters: Bool
        if mangaChapterMode {
            useChapters = true
        } else if mangaVolumeMode {
            useChapters = false
        } else {
            useChapters = UserDefaults.standard.bool(forKey: "\(sourceKey).useChapters")
        }

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
