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
            let split = trackId.split(separator: idSeparator, maxSplits: 2).map(String.init)
            if split.count == 3 {
                let state = try? await api.getState(sourceKey: split[0], url: split[1], mangaId: split[2])
                if state?.lastReadVolume == nil || state?.lastReadVolume == 0 {
                    try await api.update(
                        sourceKey: split[0],
                        url: split[1],
                        update: .init(lastReadVolume: Int(floor(highestChapterRead))), mangaId: split[2]
                    )
                }
            } else if split.count == 2 {
                // Backward compatibility
                let state = try? await api.getState(sourceKey: split[0], url: split[1])
                if state?.lastReadVolume == nil || state?.lastReadVolume == 0 {
                    try await api.update(
                        sourceKey: split[0],
                        url: split[1],
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
        if split.count == 3 {
            try await api.update(sourceKey: split[0], url: split[1], update: update, mangaId: split[2])
        } else if split.count == 2 {
            // Backward compatibility
            try await api.update(sourceKey: split[0], url: split[1], update: update)
        } else {
            throw KomgaTrackerError.invalidId
        }
    }

    func getState(trackId: String) async throws -> TrackState {
        let split = trackId.split(separator: idSeparator, maxSplits: 2).map(String.init)
        if split.count == 3 {
            if let state = try await api.getState(sourceKey: split[0], url: split[1], mangaId: split[2]) {
                return state
            } else {
                throw KomgaTrackerError.getStateFailed
            }
        } else if split.count == 2 {
            // Backward compatibility
            if let state = try await api.getState(sourceKey: split[0], url: split[1]) {
                return state
            } else {
                throw KomgaTrackerError.getStateFailed
            }
        } else {
            throw KomgaTrackerError.invalidId
        }
    }

    func search(for manga: Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let helper = KomgaHelper(sourceKey: manga.sourceId)
        let url = try helper.getServerUrl(path: "/api/v2/series/\(manga.id)")
        let apiUrl = url.absoluteString

        let state = try await api.getState(sourceKey: manga.sourceId, url: apiUrl, mangaId: manga.id)
        if state != nil {
            return [.init(id: "\(manga.sourceId)\(idSeparator)\(apiUrl)\(idSeparator)\(manga.id)", tracked: true)]
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
