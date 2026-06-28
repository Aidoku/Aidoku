//
//  MangaUpdateObject.swift
//  Aidoku
//
//  Created by axiel7 on 09/02/2024.
//

import CoreData

extension MangaUpdateObject {
    public var id: String {
        (sourceId ?? "") + (chapterId ?? "") + (mangaId ?? "")
    }

    var identifier: ChapterIdentifier {
        .init(sourceKey: sourceId ?? "", mangaKey: mangaId ?? "", chapterKey: chapterId ?? "")
    }

    func toItem() -> MangaUpdateItem {
        MangaUpdateItem(
            sourceId: sourceId,
            chapterId: chapterId,
            mangaId: mangaId,
            viewed: viewed
        )
    }
}

struct MangaUpdateItem {
    let sourceId: String?
    let chapterId: String?
    let mangaId: String?
    let viewed: Bool
}
