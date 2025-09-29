//
//  KomgaTracker.swift
//  Aidoku
//
//  Created by Skitty on 9/15/25.
//

import AidokuRunner
import Foundation

class KomgaTracker: EnhancedTracker {
    let id = "komga"
    let name = NSLocalizedString("KOMGA")
    let icon = PlatformImage(named: "komga")

    let supportedStatuses: [TrackStatus] = []
    let scoreType: TrackScoreType = .hundredPoint

    private let api = KomgaApi()

    private let idSeparator: Character = "|"

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        if let highestChapterRead {
            let split = trackId.split(separator: idSeparator, maxSplits: 2).map(String.init)
            if split.count >= 2 {
                let sourceKey = split[0]
                let url = split[1]
                let mangaKey = split[safe: 2] ?? "" // backwards compatibility

                let state = try? await api.getState(sourceKey: sourceKey, mangaKey: mangaKey, url: url)
                if state?.lastReadVolume == nil || state?.lastReadVolume == 0 {
                    try await api.update(
                        sourceKey: sourceKey,
                        mangaKey: mangaKey,
                        url: url,
                        update: .init(lastReadVolume: Int(floor(highestChapterRead)))
                    )
                }
            } else {
                throw KomgaTrackerError.invalidId
            }
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        let split = trackId.split(separator: idSeparator, maxSplits: 2).map(String.init)
        guard split.count >= 2 else { throw KomgaTrackerError.invalidId }

        try await api.update(
            sourceKey: split[0],
            mangaKey: split[safe: 2] ?? "",
            url: split[1],
            update: update
        )
    }

    func getState(trackId: String) async throws -> TrackState {
        let split = trackId.split(separator: idSeparator, maxSplits: 2).map(String.init)
        guard split.count >= 2 else { throw KomgaTrackerError.invalidId }

        if let state = try await api.getState(
            sourceKey: split[0],
            mangaKey: split[safe: 2] ?? "",
            url: split[1]
        ) {
            return state
        } else {
            throw KomgaTrackerError.getStateFailed
        }
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let helper = KomgaHelper(sourceKey: manga.sourceKey)
        let url = try helper.getServerUrl(path: "/api/v2/series/\(manga.key)")
        let apiUrl = url.absoluteString

        let state = try await api.getState(sourceKey: manga.sourceKey, mangaKey: manga.key, url: apiUrl)
        if state != nil {
            return [.init(id: "\(manga.sourceKey)\(idSeparator)\(apiUrl)\(idSeparator)\(manga.key)", tracked: true)]
        } else {
            return []
        }
    }

    func getUrl(trackId: String) async -> URL? {
        nil
    }

    func canRegister(sourceKey: String, mangaKey: String) -> Bool {
        sourceKey.hasPrefix("komga")
    }
}

enum KomgaTrackerError: Error {
    case invalidId
    case getStateFailed
    case notLoggedIn
}
