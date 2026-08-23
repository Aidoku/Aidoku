//
//  BangumiTracker.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import AidokuRunner
import Foundation

/// Bangumi tracker for Aidoku.
final class BangumiTracker: OAuthTracker {
    let id = "bangumi"
    let name = "Bangumi"
    let icon = PlatformImage(named: "bangumi")

    let api = BangumiApi()

    let callbackHost = "bangumi-auth"
    var oauthClient: OAuthClient { api.oauth }

    func getTrackerInfo() -> TrackerInfo {
        .init(supportedStatuses: TrackStatus.defaultStatuses, scoreType: .tenPoint)
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        guard let id = Int(trackId) else {
            throw BangumiTrackerError.invalidId
        }
        // set status to reading if status doesn't already exist
        let state = await api.getSubjectState(id: id)
        if state?.collect == nil {
            await api.update(subject: id, update: TrackUpdate(
                status: earliestReadDate != nil ? .reading : .planning,
                lastReadChapter: highestChapterRead,
                startReadDate: earliestReadDate
            ))
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        guard let id = Int(trackId) else {
            throw BangumiTrackerError.invalidId
        }
        let success = await api.update(subject: id, update: update)
        if !success {
            throw BangumiTrackerError.updateFailed
        }
    }

    func getState(trackId: String) async throws -> TrackState {
        guard let id = Int(trackId) else {
            throw BangumiTrackerError.invalidId
        }

        // Check if user is logged in
        guard isLoggedIn else {
            throw BangumiTrackerError.notLoggedIn
        }

        guard let result = await api.getSubjectState(id: id) else {
            throw BangumiTrackerError.getStateFailed
        }

        // Get subject info for total chapters/volumes
        let subject = await api.getSubject(id: id)

        return TrackState(
            score: result.rate,
            status: getStatus(statusString: result.collect),
            lastReadChapter: Float(result.ep_status ?? 0),
            lastReadVolume: result.vol_status.map { Int($0) },
            totalChapters: subject?.eps ?? subject?.total_episodes,
            totalVolumes: subject?.volumes,
        )
    }

    func getUrl(trackId: String) -> URL? {
        URL(string: "https://bgm.tv/subject/\(trackId)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async -> [TrackSearchItem] {
        await search(title: manga.title, nsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async -> [TrackSearchItem] {
        if
            let url = URL(string: title),
            url.host == "bgm.tv" || url.host == "bangumi.tv",
            case let pathComponents = url.pathComponents,
            pathComponents.count >= 3,
            pathComponents[1] == "subject",
            let id = Int(pathComponents[2])
        {
            // use bangumi url to search
            guard let subject = await api.getSubject(id: id) else { return [] }
            return [TrackSearchItem(
                id: String(subject.id),
                title: getDisplayTitle(for: subject),
                coverUrl: getCoverUrl(for: subject),
                description: subject.summary,
                status: getPublishingStatus(subject: subject),
                type: getSubjectType(for: subject),
                tracked: false // TODO: check if tracked
            )]
        } else {
            return await search(title: title, nsfw: includeNsfw)
        }
    }

    private func search(title: String, nsfw: Bool) async -> [TrackSearchItem] {
        guard let subjects = await api.search(query: title, nsfw: nsfw) else {
            return []
        }

        return subjects.map {
            TrackSearchItem(
                id: String($0.id),
                title: getDisplayTitle(for: $0),
                coverUrl: getCoverUrl(for: $0),
                description: $0.summary,
                status: getPublishingStatus(subject: $0),
                type: getSubjectType(for: $0),
                tracked: false
            )
        }
    }

    func getAuthenticationUrl() async -> URL? {
        await api.oauth.getAuthenticationUrl(responseType: "code", redirectUri: "aidoku://bangumi-auth")
    }

    func handleAuthenticationCallback(url: URL) async {
        guard let code = url.queryParameters?["code"] else { return }

        let oauth = await api.getAccessToken(authCode: code)
        if let oauth = oauth {
            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Tracker.\(id).oauth")
        }
    }
}

private extension BangumiTracker {
    func getDisplayTitle(for subject: BangumiSubject) -> String {
        // Prefer Chinese name if it's not empty, otherwise fall back to original name
        if let nameCn = subject.name_cn, !nameCn.isEmpty {
            return nameCn
        } else if let name = subject.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Title"
        }
    }

    func getCoverUrl(for subject: BangumiSubject) -> String? {
        // Try different image sizes in order of preference: large -> common -> medium -> small -> grid
        let possibleUrls = [
            subject.images?.large,
            subject.images?.common,
            subject.images?.medium,
            subject.images?.small,
            subject.images?.grid
        ]

        // Return the first non-nil and non-empty URL
        for url in possibleUrls {
            if let url = url, !url.isEmpty {
                return url
            }
        }

        return nil
    }

    func getStatus(statusString: String?) -> TrackStatus {
        switch statusString {
            case "wish": return .planning
            case "collect": return .completed
            case "do": return .reading
            case "on_hold": return .paused
            case "dropped": return .dropped
            case nil: return .none
            default: return .planning
        }
    }

    func getPublishingStatus(subject: BangumiSubject) -> PublishingStatus {
        // Check if subject has volumes, eps, or total_episodes > 0 (completed)
        if (subject.volumes ?? 0) > 0 || (subject.eps ?? 0) > 0 || (subject.total_episodes ?? 0) > 0 {
            return .completed
        }
        return .ongoing
    }

    func getSubjectType(for subject: BangumiSubject) -> MediaType {
        // First check series and platform if available
        if let series = subject.series {
            if !series {
                // series is false, it's a one-shot
                return .oneShot
            } else {
                // series is true, check platform
                if let platform = subject.platform, platform == "漫画" {
                    return .manga
                } else {
                    return .novel
                }
            }
        }

        // Fall back to type-based classification
        switch subject.type {
            case 1: return .manga // Book
            case 2: return .novel // Anime (but we use for manga context)
            case 3: return .novel // Music
            case 4: return .novel // Game
            case 6: return .novel // Real
            default: return .manga
        }
    }
}

enum BangumiTrackerError: Error {
    case invalidId
    case getStateFailed
    case notLoggedIn
    case updateFailed
}
