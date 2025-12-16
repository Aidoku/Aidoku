//
//  CoreDataManager+ReadingSession.swift
//  Aidoku
//
//  Created by Skitty on 12/16/25.
//

import CoreData
import Foundation

extension CoreDataManager {
    func createSession(
        chapterIdentifier: ChapterIdentifier,
        data: HistoryManager.ReadingSessionData,
        context: NSManagedObjectContext? = nil
    ) {
        let historyObject = self.getOrCreateHistory(
            sourceId: chapterIdentifier.sourceKey,
            mangaId: chapterIdentifier.mangaKey,
            chapterId: chapterIdentifier.chapterKey,
            context: context
        )
        if historyObject.dateRead == .distantPast {
            // if history object was just created, populate it with info we have
            historyObject.dateRead = data.endDate
        }
        let session = ReadingSessionObject(context: context ?? self.context)
        session.startDate = data.startDate
        session.endDate = data.endDate
        session.pagesRead = Int16(data.pagesRead)
        session.history = historyObject
    }
}
