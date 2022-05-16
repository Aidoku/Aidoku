//
//  Download.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import Foundation

enum DownloadStatus {
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

    static func from(chapter: Chapter, status: DownloadStatus = .queued) -> Download {
        Download(sourceId: chapter.sourceId, mangaId: chapter.mangaId, chapterId: chapter.id, status: status)
    }

    func toChapter() -> Chapter {
        Chapter(sourceId: sourceId, id: chapterId, mangaId: mangaId, title: nil, sourceOrder: -1)
    }
}
