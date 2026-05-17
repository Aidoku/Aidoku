//
//  TrackObject.swift
//  Aidoku
//
//  Created by Skitty on 7/20/22.
//

import Foundation

extension TrackObject {
    func toItem() -> TrackItem {
        return TrackItem(
            id: id ?? "",
            trackerId: trackerId ?? "",
            sourceId: sourceId ?? "",
            mangaId: mangaId ?? "",
            title: title,
            chapterOffset: Int(chapterOffset)
        )
    }
}
