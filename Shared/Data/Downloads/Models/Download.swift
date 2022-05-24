//
//  Download.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import Foundation

enum DownloadStatus {
    case none
    case queued
    case downloading
    case paused
    case cancelled
    case finished
    case failed
}

struct Download: Equatable {

    let sourceId: String
    let mangaId: String
    let chapterId: String

    var status: DownloadStatus = .queued

    var progress: Int = 0
    var total: Int = 0

    var manga: Manga?
    var chapter: Chapter?

    static func == (lhs: Download, rhs: Download) -> Bool {
        lhs.sourceId == rhs.sourceId && lhs.mangaId == rhs.mangaId && lhs.chapterId == rhs.chapterId
    }

    static func from(chapter: Chapter, status: DownloadStatus = .queued) -> Download {
        Download(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, status: status, chapter: chapter)
    }

    func toChapter() -> Chapter {
        if let chapter = chapter {
            return chapter
        } else {
            return Chapter(sourceId: sourceId, id: chapterId, mangaId: mangaId, title: nil, sourceOrder: -1)
        }
    }
}
