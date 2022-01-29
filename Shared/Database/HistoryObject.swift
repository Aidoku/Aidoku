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

}

extension HistoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoryObject> {
        return NSFetchRequest<HistoryObject>(entityName: "History")
    }

    @NSManaged public var dateRead: Date
    @NSManaged public var chapter: ChapterObject
    
}

extension HistoryObject : Identifiable {

}
