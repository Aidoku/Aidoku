//
//  KomgaTracker.swift
//  Aidoku
//
//  Created by Skitty on 9/15/25.
//

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
            let split = trackId.split(separator: idSeparator, maxSplits: 1).map(String.init)
            guard split.count == 2 else { throw KomgaTrackerError.invalidId }

            let state = try? await api.getState(sourceKey: split[0], url: split[1])
            if state?.lastReadVolume == nil || state?.lastReadVolume == 0 {
                try await api.update(sourceKey: split[0], url: split[1], update: .init(lastReadVolume: Int(floor(highestChapterRead))))
            }
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        let split = trackId.split(separator: idSeparator, maxSplits: 1).map(String.init)
        guard split.count == 2 else { throw KomgaTrackerError.invalidId }
        try await api.update(sourceKey: split[0], url: split[1], update: update)
    }

    func getState(trackId: String) async throws -> TrackState {
        let split = trackId.split(separator: idSeparator, maxSplits: 1).map(String.init)
        guard split.count == 2 else { throw KomgaTrackerError.invalidId }

        if let state = try await api.getState(sourceKey: split[0], url: split[1]) {
            return state
        } else {
            throw KomgaTrackerError.getStateFailed
        }
    }

    func search(for manga: Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let helper = KomgaHelper(sourceKey: manga.sourceId)
        let url = try helper.getServerUrl(path: "/api/v2/series/\(manga.id)")
        let apiUrl = url.absoluteString

        let state = try await api.getState(sourceKey: manga.sourceId, url: apiUrl)
        if state != nil {
            return [.init(id: "\(manga.sourceId)\(idSeparator)\(apiUrl)", trackerId: id, tracked: true)]
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
