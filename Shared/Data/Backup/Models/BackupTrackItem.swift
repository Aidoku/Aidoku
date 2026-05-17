//
//  BackupTrackItem.swift
//  Aidoku
//
//  Created by Skitty on 7/21/22.
//

import CoreData

struct BackupTrackItem: Codable, Hashable {
    var id: String
    var trackerId: String
    var mangaId: String
    var sourceId: String
    var title: String?
    var chapterOffset: Int?

    init(trackObject: TrackObject) {
        id = trackObject.id ?? ""
        trackerId = trackObject.trackerId ?? ""
        mangaId = trackObject.mangaId ?? ""
        sourceId = trackObject.sourceId ?? ""
        title = trackObject.title
        chapterOffset = Int(trackObject.chapterOffset)
    }

    func toObject(context: NSManagedObjectContext? = nil) -> TrackObject {
        let obj: TrackObject
        if let context = context {
            obj = TrackObject(context: context)
        } else {
            obj = TrackObject()
        }
        obj.id = id
        obj.trackerId = trackerId
        obj.mangaId = mangaId
        obj.sourceId = sourceId
        obj.title = title
        obj.chapterOffset = Int16(chapterOffset ?? 0)
        return obj
    }
}
