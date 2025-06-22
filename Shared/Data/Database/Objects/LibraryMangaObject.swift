//
//  LibraryMangaObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData

@objc(LibraryMangaObject)
public class LibraryMangaObject: NSManagedObject {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        lastOpened = Date()
        lastUpdated = Date().addingTimeInterval(-5)
        lastRead = Date()
        dateAdded = Date()
    }
}

extension LibraryMangaObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<LibraryMangaObject> {
        NSFetchRequest<LibraryMangaObject>(entityName: "LibraryManga")
    }

    @NSManaged public var lastOpened: Date
    @NSManaged public var lastUpdated: Date
    @NSManaged public var lastRead: Date?
    @NSManaged public var dateAdded: Date
    @NSManaged public var manga: MangaObject?

    @NSManaged public var categories: NSSet?

}

// MARK: Generated accessors for categories
extension LibraryMangaObject {

    @objc(addCategoriesObject:)
    @NSManaged public func addToCategories(_ value: CategoryObject)

    @objc(removeCategoriesObject:)
    @NSManaged public func removeFromCategories(_ value: CategoryObject)

//    @objc(addCategories:)
//    @NSManaged public func addToCategories(_ values: NSSet)

//    @objc(removeCategories:)
//    @NSManaged public func removeFromCategories(_ values: NSSet)

}

extension LibraryMangaObject: Identifiable {

}
