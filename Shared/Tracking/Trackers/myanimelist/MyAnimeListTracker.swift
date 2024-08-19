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

/// MyAnimeList tracker for Aidoku.
class MyAnimeListTracker: OAuthTracker {

    let id = "myanimelist"
    let name = "MyAnimeList"
    let icon = UIImage(named: "mal")

    let supportedStatuses = TrackStatus.defaultStatuses
    let scoreType: TrackScoreType = .tenPoint

    let api = MyAnimeListApi()

    let callbackHost = "myanimelist-auth"
    lazy var authenticationUrl = api.oauth.getAuthenticationUrl() ?? ""

    var oauthClient: OAuthClient { api.oauth }

    func register(trackId: String, hasReadChapters: Bool) async {
        guard let id = Int(trackId) else { return }
        // set status to reading if status doesn't already exist
        let status = await api.getMangaStatus(id: id)
        if status == nil {
            await api.updateMangaStatus(
                id: id,
                status: MyAnimeListMangaStatus(status: hasReadChapters ? "reading" : "plan_to_read")
            )
        }
    }

    func update(trackId: String, update: TrackUpdate) async {
        guard let id = Int(trackId) else { return }
        let status = MyAnimeListMangaStatus(
            isRereading: update.status != nil ? update.status?.rawValue == TrackStatus.rereading.rawValue : nil,
            numVolumesRead: update.lastReadVolume,
            numChaptersRead: update.lastReadChapter != nil ? Int(floor(update.lastReadChapter!)) : nil,
            startDate: update.startReadDate?.dateString(format: "yyyy-MM-dd"),
            finishDate: update.finishReadDate?.dateString(format: "yyyy-MM-dd"),
            status: update.status != nil ? getStatusString(status: update.status!) : nil,
            score: update.score
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
            startReadDate: status.startDate?.date(format: "yyyy-MM-dd"),
            finishReadDate: status.finishDate?.date(format: "yyyy-MM-dd")
        )
    }

    func getUrl(trackId: String) -> URL? {
        URL(string: "https://myanimelist.net/manga/\(trackId)")
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        await search(title: manga.title ?? "")
    }

    func search(title: String) async -> [TrackSearchItem] {
        (await api.search(query: title)?.data.concurrentMap { node -> TrackSearchItem in
            let details = await self.api.getMangaDetails(id: node.node.id)
            return TrackSearchItem(
                id: String(node.node.id),
                trackerId: self.id,
                title: details?.title,
                coverUrl: details?.mainPicture?.large,
                description: details?.synopsis,
                status: self.getPublishingStatus(statusString: details?.status ?? ""),
                type: self.getMediaType(typeString: details?.mediaType ?? ""),
                tracked: details?.myListStatus != nil
            )
        }) ?? []
    }

    func handleAuthenticationCallback(url: URL) async {
        if let authCode = url.queryParameters?["code"] {
            guard let oauth = await api.oauth.getAccessToken(authCode: authCode) else { return }
            token = oauth.accessToken
            UserDefaults.standard.set(try? JSONEncoder().encode(oauth), forKey: "Token.\(id).oauth")
        }
    }
}

private extension MyAnimeListTracker {

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

    func getMediaType(typeString: String) -> MediaType {
        switch typeString {
        case "unknown": return .unknown
        case "manga": return .manga
        case "novel": return .novel
        case "light_novel": return .novel
        case "manhwa": return .manhwa
        case "manhua": return .manhua
        case "oel": return .oel
        case "one_shot": return .oneShot
        case "doujinshi": return .manga
        default: return .manga
        }
    }
}
