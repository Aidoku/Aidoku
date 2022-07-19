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

    /// An array of the available trackers.
    lazy var trackers: [Tracker] = [myanimelist]

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

                if status == .planning {
                    await tracker.register(trackId: id)
                }

                if state.lastReadChapter ?? 0 < chapter.chapterNum ?? 0 ||
                    state.lastReadVolume ?? 0 < Int(chapter.volumeNum ?? 0) {
                    state.lastReadChapter = chapter.chapterNum ?? 0
                    state.lastReadVolume = Int(chapter.volumeNum ?? 0)
                }

                if Int(chapter.chapterNum ?? 0) >= state.totalChapters ?? 0 &&
                    Int(chapter.volumeNum ?? 0) >= state.totalVolumes ?? 0 &&
                    (state.status == nil || status == .reading || status == .rereading) {
                    state.status = .completed
                    state.finishReadDate = Date()
                }

                print(state)
                await tracker.update(trackId: id, state: state)
            }
        }
    }
}
