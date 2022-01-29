//
//  CategoryObject.swift
//  Aidoku
//
//  Created by Skitty on 1/28/22.
//

import Foundation
import CoreData

@objc(CategoryObject)
public class CategoryObject: NSManagedObject {

}

extension CategoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryObject> {
        return NSFetchRequest<CategoryObject>(entityName: "Category")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String
    @NSManaged public var sort: Int16
    @NSManaged public var flags: Int16
    
    @NSManaged public var libraryObjects: NSSet?
    
}

// MARK: Generated accessors for libraryObjects
extension CategoryObject {

    @objc(addLibraryObjectsObject:)
    @NSManaged public func addToLibraryObjects(_ value: LibraryMangaObject)

    @objc(removeLibraryObjectsObject:)
    @NSManaged public func removeFromLibraryObjects(_ value: LibraryMangaObject)

    @objc(addLibraryObjects:)
    @NSManaged public func addToLibraryObjects(_ values: NSSet)

    @objc(removeLibraryObjects:)
    @NSManaged public func removeFromLibraryObjects(_ values: NSSet)
    
}

extension CategoryObject : Identifiable {

}
