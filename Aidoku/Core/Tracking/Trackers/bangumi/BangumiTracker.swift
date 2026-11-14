//
//  BangumiTracker.swift
//  Aidoku
//
//  Created by dyphire on 22/9/2025.
//

import AidokuRunner
import Foundation

/// Bangumi tracker for Aidoku, backed by the Next API (next.bgm.tv/p1).
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
        let subject = try? await api.getSubject(id: id)
        if subject?.interest == nil {
            try? await api.update(subject: id, update: TrackUpdate(
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
        do {
            try await api.update(subject: id, update: update)
        } catch BangumiApiError.notLoggedIn {
            throw BangumiTrackerError.notLoggedIn
        } catch {
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

        let subject: BangumiSubject
        do {
            subject = try await api.getSubject(id: id)
        } catch BangumiApiError.notLoggedIn {
            throw BangumiTrackerError.notLoggedIn
        } catch {
            throw BangumiTrackerError.getStateFailed
        }

        // interest is nil when the subject is not collected yet
        let interest = subject.interest
        return TrackState(
            score: interest?.rate,
            status: interest.flatMap { getStatus(collectionType: $0.type) },
            lastReadChapter: interest?.epStatus.map { Float($0) },
            lastReadVolume: interest?.volStatus,
            totalChapters: subject.eps,
            totalVolumes: subject.volumes,
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
            guard let subject = try? await api.getSubject(id: id) else { return [] }
            return [trackSearchItem(for: subject)]
        } else {
            return await search(title: title, nsfw: includeNsfw)
        }
    }

    private func search(title: String, nsfw: Bool) async -> [TrackSearchItem] {
        guard let subjects = try? await api.search(query: title, nsfw: nsfw) else {
            return []
        }

        return subjects.map { trackSearchItem(for: $0) }
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
    func trackSearchItem(for subject: BangumiSubject) -> TrackSearchItem {
        TrackSearchItem(
            id: String(subject.id),
            title: getDisplayTitle(for: subject),
            coverUrl: getCoverUrl(for: subject),
            description: subject.summary,
            status: getPublishingStatus(subject: subject),
            type: getSubjectType(for: subject),
            tracked: subject.interest != nil
        )
    }

    func getDisplayTitle(for subject: BangumiSubject) -> String {
        // Prefer Chinese name if it's not empty, otherwise fall back to original name
        if let nameCn = subject.nameCN, !nameCn.isEmpty {
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

    func getStatus(collectionType: Int?) -> TrackStatus {
        // Bangumi collection types: 1=wish, 2=collect, 3=do, 4=on_hold, 5=dropped
        switch collectionType {
            case 1: return .planning
            case 2: return .completed
            case 3: return .reading
            case 4: return .paused
            case 5: return .dropped
            case nil: return .none
            default: return .planning
        }
    }

    func getPublishingStatus(subject: BangumiSubject) -> PublishingStatus {
        // Check if subject has volumes or eps > 0 (completed)
        if (subject.volumes ?? 0) > 0 || (subject.eps ?? 0) > 0 {
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
            } else if let typeCN = subject.platform?.typeCN {
                // series is true, classify by the platform carrier label
                if typeCN.contains("小说") {
                    return .novel
                } else if typeCN.contains("漫画") {
                    return .manga
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
