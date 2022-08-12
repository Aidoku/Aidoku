//
//  CoreDataManager+Category.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/11/22.
//

import Foundation

extension CoreDataManager {

    func getCategories() -> [CategoryObject] {
        let request = CategoryObject.fetchRequest()
        let objects = try? container.viewContext.fetch(request)
        return objects ?? []
    }
}
