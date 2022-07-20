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

class AniListTracker: OAuthTracker {

    let id = "anilist"
    let name = "AniList"
    let icon = UIImage(named: "anilist")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = AniListApi()

    let callbackHost = "myanimelist-auth"
    lazy var authenticationUrl = api.oauth.getAuthenticationUrl(response: "token") ?? ""

    func register(trackId: String) async {
        // Unneeded for AniList
    }

    func update(trackId: String, state: TrackState) async {
        _ = await api.update(media: Int(trackId) ?? 0, state: state)
    }

    func getState(trackId: String) async -> TrackState {
        let result = await api.getState(media: Int(trackId) ?? 0)
        if result == nil {
            return TrackState()
        }

        return TrackState(
            score: result?.mediaListEntry?.score,
            status: decodeStatus(result?.status ?? ""),
            lastReadChapter: Float(result?.mediaListEntry?.progress ?? 0),
            lastReadVolume: result?.mediaListEntry?.progressVolumes,
            totalChapters: result?.chapters,
            totalVolumes: result?.volumes,
            startReadDate: decodeDate(result?.mediaListEntry?.startedAt),
            finishReadDate: decodeDate(result?.mediaListEntry?.completedAt)
        )
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        let result = await api.search(query: manga.title ?? "")?.data.media
        if result == nil {
            return []
        }

        return [TrackSearchItem(
            id: String(result?.id ?? 0),
            trackerId: self.id,
            coverUrl: result?.coverImage?.large,
            description: result?.description,
            status: .unknown,
            type: .manga
        )]
    }

    func handleAuthenticationCallback(url: URL) async {
        guard let params = URL(string: "\(url.formatted())?\(url.fragment ?? "")") else { return }
        if let accessToken = params.queryParameters?["access_token"] {
            let oauth = OAuthResponse(
                tokenType: params.queryParameters?["token_type"],
                refreshToken: nil,
                accessToken: accessToken,
                expiresIn: Int(params.queryParameters?["expires_in"] ?? "0")
            )

            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }

    private func decodeStatus(_ value: String) -> TrackStatus {
        switch value {
        case "CURRENT": return .reading
        case "PLANNING": return .planning
        case "COMPLETED": return .completed
        case "DROPPED": return .dropped
        case "PAUSED": return .paused
        case "REPEATING": return .reading
        default: return .planning
        }
    }

    private func decodeDate(_ value: AniListDate?) -> Date? {
        if let day = value?.day, let month = value?.month, let year = value?.year {
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        }
        return nil
    }
}
