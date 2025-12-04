//
//  TrackerSyncTests.swift
//  Aidoku
//
//  Created by Skitty on 11/17/25.
//

import AidokuRunner
import Foundation
import Testing

@testable import Aidoku

actor TestableTracker: Tracker {
    let id = "test"
    let name = "Test"
    let icon: Aidoku.PlatformImage? = nil
    let isLoggedIn = true

    var lastReadChapter: Float?
    var lastReadVolume: Int?

    func setLastReadChapter(_ chapter: Float?) {
        lastReadChapter = chapter
    }
    func setLastReadVolume(_ volume: Int?) {
        lastReadVolume = volume
    }

    func getTrackerInfo() async throws -> Aidoku.TrackerInfo {
        .init(supportedStatuses: [], scoreType: .tenPoint)
    }

    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        nil
    }

    func update(trackId: String, update: Aidoku.TrackUpdate) async throws {}

    func getState(trackId: String) async throws -> Aidoku.TrackState {
        .init(
            score: nil,
            status: nil,
            lastReadChapter: lastReadChapter,
            lastReadVolume: lastReadVolume,
            totalChapters: nil,
            totalVolumes: nil,
            startReadDate: nil,
            finishReadDate: nil
        )
    }

    func getUrl(trackId: String) async -> URL? {
        nil
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [Aidoku.TrackSearchItem] {
        []
    }

    func search(title: String, includeNsfw: Bool) async throws -> [Aidoku.TrackSearchItem] {
        []
    }

    func logout() {}
}

@Suite struct TrackerSyncTests {
    static let testId = "test"
    static let testManga: AidokuRunner.Manga = .init(sourceKey: "test", key: "test", title: "Test")

    @Test func testChapterNumbers() async {
        let tracker = TestableTracker()
        await tracker.setLastReadChapter(5)

        let result = await TrackerManager.shared.getChaptersToSyncProgressFromTracker(
            tracker: tracker,
            trackId: Self.testId,
            manga: Self.testManga,
            chapters: (1...10).map {
                .init(
                    key: "\($0)",
                    title: "\($0)",
                    chapterNumber: Float($0)
                )
            },
            currentHighestRead: 0
        )

        // chapters 1-5
        #expect(result.count == 5)
    }

    @Test func testVolumeNumbers() async {
        let tracker = TestableTracker()
        await tracker.setLastReadChapter(2)
        await tracker.setLastReadVolume(1)

        let chapters: [AidokuRunner.Chapter] = (1...10).map {
            .init(
                key: "\($0)",
                title: "\($0)",
                chapterNumber: Float($0),
                volumeNumber: $0 <= 5 ? 1 : 2
            )
        }

        var result = await TrackerManager.shared.getChaptersToSyncProgressFromTracker(
            tracker: tracker,
            trackId: Self.testId,
            manga: Self.testManga,
            chapters: chapters,
            currentHighestRead: 0
        )

        // chapters 1-2, lastReadChapter should be prioritized
        #expect(result.count == 2)

        await tracker.setLastReadChapter(nil)

        result = await TrackerManager.shared.getChaptersToSyncProgressFromTracker(
            tracker: tracker,
            trackId: Self.testId,
            manga: Self.testManga,
            chapters: chapters,
            currentHighestRead: 0
        )

        // chapters 1-5, lastReadVolume should be used and match all chapters with volume 1
        #expect(result.count == 5)
    }

    @Test func testChapterNumbersWithHistory() async {
        let tracker = TestableTracker()
        await tracker.setLastReadChapter(5)

        let chapters: [AidokuRunner.Chapter] = (1...10).map {
            .init(
                key: "\($0)",
                title: "\($0)",
                chapterNumber: Float($0)
            )
        }

        var result = await TrackerManager.shared.getChaptersToSyncProgressFromTracker(
            tracker: tracker,
            trackId: Self.testId,
            manga: Self.testManga,
            chapters: chapters,
            currentHighestRead: 5
        )

        // highest read matches tracker's last read, so no chapters to sync
        #expect(result.isEmpty)

        result = await TrackerManager.shared.getChaptersToSyncProgressFromTracker(
            tracker: tracker,
            trackId: Self.testId,
            manga: Self.testManga,
            chapters: chapters,
            currentHighestRead: 4
        )

        // all matching chapters should be returned even if there's only one unread
        #expect(result.count == 5)
    }
}
