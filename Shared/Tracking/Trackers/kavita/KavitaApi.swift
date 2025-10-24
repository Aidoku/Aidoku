//
//  KomgaApi.swift
//  Aidoku
//
//  Created by Skitty on 10/23/25.
//

import Foundation

class KavitaApi {
    func getState(sourceKey: String, seriesId: String) async throws -> TrackState? {
        let helper = KavitaHelper(sourceKey: sourceKey)
        let volumes: [KavitaVolume] = try await helper.request(path: "/api/Series/volumes?seriesId=\(seriesId)")

        var totalVolumes = 0
        var totalChapters = 0

        for volume in volumes {
            if volume.number > 0 && volume.number < 100000 {
                totalVolumes = max(totalVolumes, volume.number)
            }
            let chapterMax = volume.chapters
                .compactMap { chapter -> Int? in
                    guard let number = Float(chapter.number) else { return nil }
                    if number > 0 && number < 100000 {
                        return Int(floor(number))
                    } else {
                        return nil
                    }
                }
                .max()
            if let chapterMax {
                totalChapters = max(totalChapters, chapterMax)
            }
        }

        let latestChapter: KavitaVolume.Chapter? = try? await helper.request(path: "/api/Tachiyomi/latest-chapter?seriesId=\(seriesId)")

        return .init(
            lastReadChapter: latestChapter.flatMap { chapter -> Float? in
                guard let number = Float(chapter.number) else { return nil }
                if number > 0 && number < 100000 {
                    return number
                } else {
                    return nil
                }
            },
            totalChapters: totalChapters,
            totalVolumes: totalVolumes
        )
    }

    func update(sourceKey: String, seriesId: String, update: TrackUpdate) async throws {
        guard let lastReadChapter = update.lastReadChapter else { return }

        let helper = KavitaHelper(sourceKey: sourceKey)

        let _: Bool = try await helper.request(
            path: "/api/Tachiyomi/mark-chapter-until-as-read?seriesId=\(seriesId)&chapterNumber=\(lastReadChapter)",
            method: .POST,
            body: Data("{}".utf8)
        )
    }

    func updateReadProgress(
        sourceKey: String,
        seriesId: Int,
        chapterId: Int,
        progress: ChapterReadProgress
    ) async throws {
        let helper = KavitaHelper(sourceKey: sourceKey)

        struct Response: Decodable {
            let libraryId: Int
            let volumeId: Int
            let pages: Int
        }
        let response: Response = try await helper.request(path: "/api/reader/chapter-info?chapterId=\(chapterId)")

        let pageNum = if progress.completed {
            response.pages
        } else {
            progress.page
        }

        struct Payload: Encodable {
            let libraryId: Int
            let seriesId: Int
            let volumeId: Int
            let chapterId: Int
            let pageNum: Int
        }
        let payload = Payload(
            libraryId: response.libraryId,
            seriesId: seriesId,
            volumeId: response.volumeId,
            chapterId: chapterId,
            pageNum: pageNum
        )

        let _: Bool = try await helper.request(
            path: "/api/reader/progress",
            method: .POST,
            body: JSONEncoder().encode(payload)
        )
    }

    func getSeriesReadProgress(sourceKey: String, seriesId: String) async throws -> [String: ChapterReadProgress] {
        let helper = KavitaHelper(sourceKey: sourceKey)
        let volumes: [KavitaVolume] = try await helper.request(path: "/api/Series/volumes?seriesId=\(seriesId)")

        var progressMap: [String: ChapterReadProgress] = [:]

        for volume in volumes {
            for chapter in volume.chapters {
                let completed = chapter.pagesRead == chapter.pages
                let page = chapter.pagesRead
                if page == 0 && !completed {
                    continue // no progress, skip
                }
                progressMap["\(chapter.id)"] = .init(
                    completed: completed,
                    page: chapter.pagesRead,
                    date: chapter.lastReadingProgressUtc
                )
            }
        }

        return progressMap
    }
}
