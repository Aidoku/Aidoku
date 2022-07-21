//
//  MyAnimeListTracker.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation
import AuthenticationServices

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// Aidoku tracker for MyAnimeList.
class MyAnimeListTracker: OAuthTracker {

    let id = "myanimelist"
    let name = "MyAnimeList"
    let icon = UIImage(named: "mal")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = MyAnimeListApi()

    let callbackHost = "myanimelist-auth"
    lazy var authenticationUrl = api.authenticationUrl ?? ""

    func register(trackId: String) async {
        guard let id = Int(trackId) else { return }
        await api.updateMangaStatus(id: id, status: MyAnimeListMangaStatus(status: "reading"))
    }

    func update(trackId: String, state: TrackState) async {
        guard let id = Int(trackId) else { return }
        let status = MyAnimeListMangaStatus(
            isRereading: state.status?.rawValue == TrackStatus.rereading.rawValue,
            numVolumesRead: state.lastReadVolume,
            numChaptersRead: state.lastReadChapter != nil ? Int(floor(state.lastReadChapter!)) : nil,
            startDate: state.startReadDate?.ISO8601Format(),
            finishDate: state.finishReadDate?.ISO8601Format(),
            status: state.status != nil ? getStatusString(status: state.status!) : nil,
            score: state.score
        )
        await api.updateMangaStatus(id: id, status: status)
    }

    func getState(trackId: String) async -> TrackState {
        guard let id = Int(trackId),
              let manga = await api.getMangaWithStatus(id: id),
              let status = manga.myListStatus else { return TrackState() }
        return TrackState(
            score: status.score,
            status: getStatus(statusString: status.status ?? ""),
            lastReadChapter: status.numChaptersRead != nil ? Float(status.numChaptersRead!) : nil,
            lastReadVolume: status.numVolumesRead,
            totalChapters: manga.numChapters,
            totalVolumes: manga.numVolumes,
            startReadDate: status.startDate?.isoDate(),
            finishReadDate: status.finishDate?.isoDate()
        )
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        await search(title: manga.title ?? "")
    }

    func search(title: String) async -> [TrackSearchItem] {
        (try? await api.search(query: title)?.data.concurrentMap { node -> TrackSearchItem in
            let details = await self.api.getMangaDetails(id: node.node.id)
            return TrackSearchItem(
                id: String(node.node.id),
                trackerId: self.id,
                title: details?.title,
                coverUrl: details?.mainPicture?.large,
                description: details?.synopsis,
                status: self.getPublishingStatus(statusString: details?.status ?? ""),
                type: self.getMediaType(typeString: details?.mediaType ?? "")
            )
        }) ?? []
    }

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            guard let oauth = await api.getAccessToken(authCode: authCode) else { return }
            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }

    func logout() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "Token.\(id).token")
        UserDefaults.standard.removeObject(forKey: "Token.\(id).oauth")
    }
}

extension MyAnimeListTracker {

    func getStatus(statusString: String) -> TrackStatus? {
        switch statusString {
        case "reading": return .reading
        case "plan_to_read": return .planning
        case "completed": return .completed
        case "on_hold": return .paused
        case "dropped": return .dropped
        default: return nil
        }
    }

    func getStatusString(status: TrackStatus) -> String? {
        switch status.rawValue {
        case 1: return "reading"
        case 2: return "plan_to_read"
        case 3: return "completed"
        case 4: return "on_hold"
        case 5: return "dropped"
        default: return nil
        }
    }

    func getPublishingStatus(statusString: String) -> PublishingStatus {
        switch statusString {
        case "currently_publishing": return .ongoing
        case "finished": return .completed
        case "not_yet_published": return .notPublished
        default: return .ongoing
        }
    }

    func getMediaType(typeString: String) -> MediaType? {
        switch typeString {
        case "unknown": return .unknown
        case "manga": return .manga
        case "novel": return .novel
        case "manhwa": return .manhwa
        case "manhua": return .manhua
        case "oel": return .oel
        default: return .manga
        }
    }
}
