//
//  AniListTracker.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import AidokuRunner
import Foundation

/// AniList tracker for Aidoku.
final class AniListTracker: OAuthTracker {
    let id = "anilist"
    let name = "AniList"
    let icon = PlatformImage(named: "anilist")

    let api = AniListApi()

    let callbackHost = "anilist-auth"
    var oauthClient: OAuthClient { api.oauth }

    func getTrackerInfo() async -> TrackerInfo {
        let scoreType: TrackScoreType
        let scoreOptions: [(String, Int)]
        if isLoggedIn {
            let scoreFormat = await api.getStoreType()
            switch scoreFormat {
                case "POINT_100":
                    scoreType = .hundredPoint
                    scoreOptions = []
                case "POINT_10_DECIMAL":
                    scoreType = .tenPointDecimal
                    scoreOptions = []
                case "POINT_10":
                    scoreType = .tenPoint
                    scoreOptions = []
                case "POINT_5":
                    scoreType = .optionList
                    scoreOptions = Array(0...5).map { ("\($0) ★", $0 == 0 ? 0 : $0 * 20 - 10) }
                case "POINT_3":
                    scoreType = .optionList
                    scoreOptions = [
                        ("-", 0),
                        ("😦", 35),
                        ("😐", 60),
                        ("😊", 85)
                    ]
                default:
                    scoreType = .tenPoint
                    scoreOptions = []
            }
        } else {
            scoreType = .tenPoint
            scoreOptions = []
        }
        return .init(
            supportedStatuses: TrackStatus.defaultStatuses,
            scoreType: scoreType,
            scoreOptions: scoreOptions
        )
    }

    func option(for score: Int, options: [(String, Int)]) -> String? {
        let isSmilies = options.count == 4
        let isStars = options.count == 6
        if isSmilies {
            // smiley faces
            if score == 0 {
                return options[0].0
            } else if score <= 35 {
                return options[1].0
            } else if score <= 60 {
                return options[2].0
            } else {
                return options[3].0
            }
        } else if isStars {
            // stars
            if score == 0 {
                return options[0].0
            } else {
                let index = Int(max(1, min((Float(score) + 10) / 20, 5)).rounded())
                return options[index].0
            }
        }
        return nil
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        guard let id = Int(trackId) else {
            throw AniListTrackerError.invalidId
        }
        // set status to reading if status doesn't already exist
        let state = await api.getMediaState(id: id)
        if state?.mediaListEntry?.status == nil {
            await api.update(media: id, update: TrackUpdate(
                status: earliestReadDate != nil ? .reading : .planning,
                lastReadChapter: highestChapterRead,
                startReadDate: earliestReadDate
            ))
        }
        return nil
    }

    func update(trackId: String, update: TrackUpdate) async throws {
        guard let id = Int(trackId) else {
            throw AniListTrackerError.invalidId
        }
        var update = update
        let scoreType = await api.getStoreType()
        if scoreType == "POINT_10" && update.score != nil {
            update.score = update.score! * 10
        }
        await api.update(media: id, update: update)
    }

    func getState(trackId: String) async throws -> TrackState {
        guard let id = Int(trackId) else {
            throw AniListTrackerError.invalidId
        }
        guard let result = await api.getMediaState(id: id) else {
            throw AniListTrackerError.getStateFailed
        }

        let score: Int?
        let scoreType = await api.getStoreType()
        if let scoreRaw = result.mediaListEntry?.score {
            score = scoreType == "POINT_10" ? Int(scoreRaw / 10) : Int(scoreRaw)
        } else {
            score = nil
        }

        return TrackState(
            score: score,
            status: getStatus(statusString: result.mediaListEntry?.status),
            lastReadChapter: Float(result.mediaListEntry?.progress ?? 0),
            lastReadVolume: result.mediaListEntry?.progressVolumes,
            totalChapters: result.chapters,
            totalVolumes: result.volumes,
            startReadDate: decodeDate(result.mediaListEntry?.startedAt),
            finishReadDate: decodeDate(result.mediaListEntry?.completedAt)
        )
    }

    func getUrl(trackId: String) -> URL? {
        URL(string: "https://anilist.co/manga/\(trackId)")
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async -> [TrackSearchItem] {
        await search(title: manga.title, nsfw: includeNsfw)
    }

    func search(title: String, includeNsfw: Bool) async -> [TrackSearchItem] {
        if
            let url = URL(string: title),
            url.host == "anilist.co",
            case let pathComponents = url.pathComponents,
            pathComponents.count >= 3,
            let id = Int(pathComponents[2])
        {
            // use anilist url to search
            guard let media = await api.getMedia(id: id) else { return [] }
            return [TrackSearchItem(
                id: String(media.id ?? 0),
                title: media.title?.userPreferred,
                coverUrl: media.coverImage?.medium,
                description: media.description,
                status: getPublishingStatus(statusString: media.status ?? ""),
                type: getMediaType(typeString: media.format ?? ""),
                tracked: media.mediaListEntry != nil
            )]
        } else {
            return await search(title: title, nsfw: includeNsfw)
        }
    }

    private func search(title: String, nsfw: Bool) async -> [TrackSearchItem] {
        guard let page = await api.search(query: title, nsfw: nsfw) else {
            return []
        }

        return page.media.map {
            TrackSearchItem(
                id: String($0.id ?? 0),
                title: $0.title?.userPreferred,
                coverUrl: $0.coverImage?.medium,
                description: $0.description,
                status: getPublishingStatus(statusString: $0.status ?? ""),
                type: getMediaType(typeString: $0.format ?? ""),
                tracked: $0.mediaListEntry != nil
            )
        }
    }

    func getAuthenticationUrl() async -> URL? {
        await api.oauth.getAuthenticationUrl(responseType: "token")
    }

    func handleAuthenticationCallback(url: URL) async {
        var components = URLComponents()
        components.query = url.fragment
        guard let queryItems = components.queryItems else { return }
        let params = queryItems.reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        guard let accessToken = params["access_token"] else { return }
        let oauth = OAuthResponse(
            tokenType: params["token_type"],
            refreshToken: nil,
            accessToken: accessToken,
            expiresIn: Int(params["expires_in"] ?? "0")
        )

        token = oauth.accessToken
        UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Tracker.\(id).oauth")
    }
}

private extension AniListTracker {
    func getStatus(statusString: String?) -> TrackStatus {
        switch statusString {
            case "CURRENT": return .reading
            case "PLANNING": return .planning
            case "COMPLETED": return .completed
            case "DROPPED": return .dropped
            case "PAUSED": return .paused
            case "REPEATING": return .rereading
            case nil: return .none
            default: return .planning
        }
    }

    func getPublishingStatus(statusString: String) -> PublishingStatus {
        switch statusString {
            case "FINISHED": return .completed
            case "RELEASING": return .ongoing
            case "NOT_YET_RELEASED": return .notPublished
            case "CANCELLED": return .cancelled
            case "HIATUS": return .hiatus
            default: return .unknown
        }
    }

    func getMediaType(typeString: String) -> MediaType {
        switch typeString {
            case "MANGA": return .manga
            case "NOVEL": return .novel
            case "ONE_SHOT": return .oneShot
            default: return .unknown
        }
    }

    private func decodeDate(_ value: AniListDate?) -> Date? {
        if let day = value?.day, let month = value?.month, let year = value?.year {
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        }
        return nil
    }
}

enum AniListTrackerError: Error {
    case invalidId
    case getStateFailed
}
