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
            chapterId: .init(
                sourceKey: sourceId ?? "",
                mangaKey: mangaId ?? "",
                chapterKey: chapterId ?? ""
            ),
            viewed: viewed
        )
    }
}

struct MangaUpdateItem {
    let chapterId: ChapterIdentifier
    let viewed: Bool
}
