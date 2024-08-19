//
//  AniListTracker.swift
//  Aidoku
//
//  Created by Koding Dev on 19/7/2022.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// AniList tracker for Aidoku.
class AniListTracker: OAuthTracker {

    let id = "anilist"
    let name = "AniList"
    let icon = UIImage(named: "anilist")

    let supportedStatuses = TrackStatus.defaultStatuses
    var scoreType: TrackScoreType = .tenPoint
    var scoreOptions: [(String, Int)] = []
    private var anilistScoreType: String?

    let api = AniListApi()

    let callbackHost = "anilist-auth"
    lazy var authenticationUrl = api.oauth.getAuthenticationUrl(responseType: "token") ?? ""

    var oauthClient: OAuthClient { api.oauth }

    init() {
        // get user score type preference
        Task {
            await getScoreType()
        }
    }

    func getScoreType() async {
        guard isLoggedIn else { return }
        let user = await api.getUser()
        anilistScoreType = user?.mediaListOptions?.scoreFormat
        switch user?.mediaListOptions?.scoreFormat {
        case "POINT_100": scoreType = .hundredPoint
        case "POINT_10_DECIMAL": scoreType = .tenPointDecimal
        case "POINT_10": scoreType = .tenPoint
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
        default: break
        }
    }

    func option(for score: Int) -> String? {
        switch anilistScoreType {
        case "POINT_5":
            if score == 0 {
                return scoreOptions[0].0
            } else {
                let index = Int(max(1, min((Float(score) + 10) / 20, 5)).rounded())
                return scoreOptions[index].0
            }
        case "POINT_3":
            if score == 0 {
                return scoreOptions[0].0
            } else if score <= 35 {
                return scoreOptions[1].0
            } else if score <= 60 {
                return scoreOptions[2].0
            } else {
                return scoreOptions[3].0
            }
        default:
            return nil
        }
    }

    func register(trackId: String, hasReadChapters: Bool) async {
        guard let id = Int(trackId) else { return }
        // set status to reading if status doesn't already exist
        let state = await api.getMediaState(id: id)
        if state?.mediaListEntry?.status == nil {
            await api.update(media: id, update: TrackUpdate(status: hasReadChapters ? .reading : .planning))
        }
    }

    func update(trackId: String, update: TrackUpdate) async {
        guard let id = Int(trackId) else { return }
        var update = update
        if scoreType == .tenPoint && update.score != nil {
            update.score = update.score! * 10
        }
        await api.update(media: id, update: update)
    }

    func getState(trackId: String) async -> TrackState {
        guard
            let id = Int(trackId),
            let result = await api.getMediaState(id: id)
        else { return TrackState() }

        let score: Int?
        if let scoreRaw = result.mediaListEntry?.score {
            score = scoreType == .tenPoint ? Int(scoreRaw / 10) : Int(scoreRaw)
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

    func search(for manga: Manga) async -> [TrackSearchItem] {
        await search(title: manga.title ?? "", nsfw: manga.nsfw != .safe)
    }

    func search(title: String) async -> [TrackSearchItem] {
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
                trackerId: self.id,
                title: media.title?.english ?? media.title?.romaji,
                coverUrl: media.coverImage?.medium,
                description: media.description,
                status: getPublishingStatus(statusString: media.status ?? ""),
                type: getMediaType(typeString: media.format ?? ""),
                tracked: media.mediaListEntry != nil
            )]
        } else {
            return await search(title: title, nsfw: false)
        }
    }

    private func search(title: String, nsfw: Bool) async -> [TrackSearchItem] {
        guard let page = await api.search(query: title, nsfw: nsfw) else {
            return []
        }

        return page.media.map {
            TrackSearchItem(
                id: String($0.id ?? 0),
                trackerId: self.id,
                title: $0.title?.english ?? $0.title?.romaji,
                coverUrl: $0.coverImage?.medium,
                description: $0.description,
                status: getPublishingStatus(statusString: $0.status ?? ""),
                type: getMediaType(typeString: $0.format ?? ""),
                tracked: $0.mediaListEntry != nil
            )
        }
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
        UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")

        await getScoreType()
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
