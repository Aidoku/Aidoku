//
//  HistoryObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData

@objc(HistoryObject)
public class HistoryObject: NSManagedObject {

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        progress = 0
        completed = false
    }
}

extension HistoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoryObject> {
        NSFetchRequest<HistoryObject>(entityName: "History")
    }

    @NSManaged public var dateRead: Date
    @NSManaged public var sourceId: String
    @NSManaged public var chapterId: String
    @NSManaged public var mangaId: String

    @NSManaged public var progress: Int16
    @NSManaged public var completed: Bool

}

extension HistoryObject: Identifiable {

}
