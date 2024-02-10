//
//  UpdateObject.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
//

import Foundation
import CoreData

@objc(MangaUpdateObject)
public class MangaUpdateObject: NSManagedObject {

}

extension MangaUpdateObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MangaUpdateObject> {
        NSFetchRequest<MangaUpdateObject>(entityName: "MangaUpdate")
    }

    @NSManaged public var sourceId: String
    @NSManaged public var chapterId: String
    @NSManaged public var mangaId: String

    @NSManaged public var date: Date
    @NSManaged public var viewed: Bool

    @NSManaged public var chapter: ChapterObject?
}

extension MangaUpdateObject: Identifiable {
    public var id: String {
        sourceId + chapterId + mangaId
    }
}
