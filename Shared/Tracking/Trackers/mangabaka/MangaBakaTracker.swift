//
//  MangaBakaTracker.swift
//  Aidoku
//
//  Created by Skitty on 2/24/26.
//

import AidokuRunner
import Foundation

/// MangaBaka tracker for Aidoku.
final class MangaBakaTracker: OAuthTracker {
    let id = "mangabaka"
    let name = "MangaBaka"
    let icon = PlatformImage(named: "mangabaka")

    let api = MangaBakaApi()

    let callbackHost = "mangabaka-auth"
    var oauthClient: OAuthClient { api.oauth }

    private let dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

    func getTrackerInfo() -> TrackerInfo {
        .init(supportedStatuses: TrackStatus.defaultStatuses, scoreType: .hundredPoint)
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        guard let id = Int(trackId) else {
            throw MangaBakaTrackerError.invalidId
        }
        // set status to reading if status doesn't already exist
        let entry = try? await api.getLibraryEntry(seriesId: id)
        if entry == nil {
            try await api.updateLibraryEntry(seriesId: id, create: true, data: .init(
                state: highestChapterRead != nil ? .reading : .planToRead,
                progressChapter: highestChapterRead.flatMap { Int(floor($0)) },
                startDate: earliestReadDate?.dateString(format: dateFormat)
            ))
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        guard let id = Int(trackId) else {
            throw MangaBakaTrackerError.invalidId
        }
        let data = MangaBakaLibraryEntry(
            id: nil,
            seriesId: nil,
            state: update.status.flatMap(MangaBakaLibraryState.init),
            rating: update.score,
            progressChapter: update.lastReadChapter.flatMap { Int(floor($0)) },
            progressVolume: update.lastReadVolume,
            startDate: update.startReadDate?.dateString(format: dateFormat),
            finishDate: update.finishReadDate?.dateString(format: dateFormat)
        )
        try await api.updateLibraryEntry(seriesId: id, data: data)
    }

    func getState(trackId: String) async throws -> TrackState {
        guard let id = Int(trackId) else {
            throw MangaBakaTrackerError.invalidId
        }
        let series = try await api.getSeries(id: id)
        let libraryEntry = try await api.getLibraryEntry(seriesId: id)
        return TrackState(
            score: libraryEntry.rating,
            status: libraryEntry.state?.into(),
            lastReadChapter: libraryEntry.progressChapter.flatMap(Float.init),
            lastReadVolume: libraryEntry.progressVolume,
            totalChapters: series.totalChapters.flatMap(Int.init),
            totalVolumes: series.finalVolume.flatMap(Int.init),
            startReadDate: libraryEntry.startDate?.date(format: dateFormat),
            finishReadDate: libraryEntry.finishDate?.date(format: dateFormat)
        )
    }

    func getUrl(trackId: String) -> URL? {
        URL(string: "https://mangabaka.org/\(trackId)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        try await search(title: manga.title, includeNsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let results = try await api.search(query: title, nsfw: includeNsfw)
        let libraryEntries = try await api.getLibraryEntries(seriesIds: results.map { $0.id })
        return results.map { series in
            TrackSearchItem(
                id: String(series.id),
                title: series.title,
                coverUrl: series.cover.raw.url,
                description: series.description,
                status: series.status.into(),
                type: series.type.into(),
                tracked: libraryEntries.contains(where: { $0.seriesId == series.id })
            )
        }
    }

    func getAuthenticationUrl() async -> URL? {
        await api.oauth.getAuthenticationUrl(
            redirectUri: "aidoku://\(callbackHost)",
            extraQueryItems: ["scope": "library.read+library.write+profile+offline_access"]
        )
    }

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            guard let oauth = await api.oauth.getAccessToken(
                authCode: authCode,
                redirectUri: "aidoku://\(callbackHost)"
            ) else {
                return
            }
            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Tracker.\(id).oauth")
        }
    }
}

enum MangaBakaTrackerError: Error {
    case invalidId
}
