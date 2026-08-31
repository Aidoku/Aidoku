//
//  TrackObject.swift
//  Aidoku
//
//  Created by Skitty on 7/20/22.
//

import Foundation

extension TrackObject {
    func toItem() -> TrackItem {
       TrackItem(
            id: id ?? "",
            trackerId: trackerId ?? "",
            mangaId: .init(sourceKey: sourceId ?? "", mangaKey: mangaId ?? ""),
            title: title,
            chapterOffset: Int(chapterOffset)
        )
    }
}
