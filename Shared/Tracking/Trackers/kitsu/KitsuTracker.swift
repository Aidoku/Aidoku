//  KitsuTracker.swift
//  Aidoku
//
//  Kitsu tracker implementation

import AidokuRunner
import AuthenticationServices
import Foundation

final class KitsuTracker: OAuthTracker {
    let id = "kitsu"
    let name = "Kitsu"
    let icon = PlatformImage(named: "kitsu")

    let api = KitsuApi()

    let callbackHost = "kitsu-auth"
    var oauthClient: OAuthClient { api.oauth }

    func getTrackerInfo() async throws -> TrackerInfo {
        .init(supportedStatuses: TrackStatus.defaultStatuses, scoreType: .tenPointDecimal)
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        await api.updateLibraryEntry(
            animeId: trackId,
            progress: highestChapterRead != nil ? Int(highestChapterRead!) : nil,
            status: highestChapterRead != nil ? "current" : "planned"
        )
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        await api.updateLibraryEntry(
            animeId: trackId,
            progress: update.lastReadChapter != nil ? Int(update.lastReadChapter!) : nil,
            status: update.status != nil ? getStatusString(status: update.status!) : nil,
            rating: update.score
        )
    }

    func getState(trackId: String) async throws -> TrackState {
        guard let entry = await api.getLibraryEntry(animeId: trackId) else {
            return TrackState()
        }
        return TrackState(
            score: entry.ratingTwenty != nil ? Int(entry.ratingTwenty! / 2) : nil,
            status: getStatus(statusString: entry.status ?? ""),
            lastReadChapter: entry.progress != nil ? Float(entry.progress!) : nil,
            totalChapters: nil
        )
    }

    func getUrl(trackId: String) async -> URL? {
        URL(string: "https://kitsu.io/anime/\(trackId)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        await search(title: manga.title, includeNsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        guard let results = await api.searchAnime(query: title) else { return [] }
        return results.data.map { item in
            TrackSearchItem(
                id: item.id,
                title: item.attributes.canonicalTitle,
                coverUrl: item.attributes.posterImage?.original,
                description: item.attributes.synopsis
            )
        }
    }

    func logout() async throws {
        token = nil
    }

    private func getStatusString(status: TrackStatus) -> String {
        switch status {
        case .reading: return "current"
        case .planning: return "planned"
        case .completed: return "completed"
        case .paused: return "on_hold"
        case .dropped: return "dropped"
        default: return "current"
        }
    }

    private func getStatus(statusString: String) -> TrackStatus? {
        switch statusString {
        case "current": return .reading
        case "planned": return .planning
        case "completed": return .completed
        case "on_hold": return .paused
        case "dropped": return .dropped
        default: return nil
        }
    }
}
