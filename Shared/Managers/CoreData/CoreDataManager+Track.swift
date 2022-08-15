//
//  CoreDataManager+Track.swift
//  Aidoku
//
//  Created by Skitty on 8/15/22.
//

import CoreData

extension CoreDataManager {

    /// Remove all track objects.
    func clearTracks(context: NSManagedObjectContext? = nil) {
        clear(request: TrackObject.fetchRequest(), context: context)
    }
}
