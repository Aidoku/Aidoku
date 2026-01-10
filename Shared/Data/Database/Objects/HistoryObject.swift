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
        dateRead = Date.distantPast
        progress = -1
        total = 0
        completed = false
        scrollPosition = 0
    }
}

extension HistoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoryObject> {
        NSFetchRequest<HistoryObject>(entityName: "History")
    }

    @NSManaged public var dateRead: Date?
    @NSManaged public var sourceId: String
    @NSManaged public var chapterId: String
    @NSManaged public var mangaId: String

    @NSManaged public var progress: Int16
    @NSManaged public var total: Int16
    @NSManaged public var completed: Bool
    @NSManaged public var scrollPosition: Double

    @NSManaged public var chapter: ChapterObject?
    @NSManaged public var sessions: NSSet?
}

extension HistoryObject {
    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: ReadingSessionObject)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: ReadingSessionObject)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: NSSet)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: NSSet)
}

extension HistoryObject: Identifiable {

}
