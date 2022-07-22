//
//  TrackerManager.swift
//  Aidoku
//
//  Created by Skitty on 6/14/22.
//

import Foundation

/// An interface to interact with title tracking services.
class TrackerManager {
    /// The shared tracker mangaer instance.
    static let shared = TrackerManager()

    /// An instance of the MyAnimeList tracker.
    let myanimelist = MyAnimeListTracker()

    /// An instance of the AniList tracker.
    let anilist = AniListTracker()

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [myanimelist, anilist]

    /// A boolean indicating if there is a tracker that is currently logged in.
    var hasAvailableTrackers: Bool {
        trackers.contains { $0.isLoggedIn }
    }

    /// Get the instance of the tracker with the specified id.
    func getTracker(id: String) -> Tracker? {
        trackers.first {
            $0.id == id
        }
    }

    /// Updates a chapter across all authenticated trackers
    func setCompleted(chapter: Chapter) async {
        let manga = await DataManager.shared.getManga(sourceId: chapter.sourceId, mangaId: chapter.mangaId)
        if manga == nil {
            return
        }

        for tracker in trackers {
            if !tracker.isLoggedIn {
                continue
            }

            let results = await tracker.search(for: manga!)
            if !results.isEmpty {
                let id = results.first?.id ?? ""
                var state = await tracker.getState(trackId: id)
                let status = state.status ?? .planning

                if status != .reading && status != .rereading {
                    state.startReadDate = Date()
                    state.status = .reading
                    await tracker.register(trackId: id)
                }

                let chapterNum = chapter.chapterNum ?? 0
                let volumeNum = Int(chapter.volumeNum ?? 0)

                if state.lastReadChapter ?? 0 < chapterNum ||
                    state.lastReadVolume ?? 0 < volumeNum {
                    state.lastReadChapter = chapterNum
                    state.lastReadVolume = volumeNum
                }

                if Int(chapterNum) >= state.totalChapters ?? 0 &&
                    volumeNum >= state.totalVolumes ?? 0 &&
                    (state.status == nil || status == .reading || status == .rereading) {
                    state.status = .completed
                    state.finishReadDate = Date()
                }

                await tracker.update(trackId: id, state: state)
            }
        }
    }
}
