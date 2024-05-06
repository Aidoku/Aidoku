//
//  MangaUpdateObject.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import CoreData

extension MangaUpdateObject {
    public var id: String {
        (sourceId ?? "") + (chapterId ?? "") + (mangaId ?? "")
    }
}
