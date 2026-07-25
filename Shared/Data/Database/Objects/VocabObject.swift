//
//  VocabObject.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

extension VocabObject {
    func toEntry() -> VocabEntry? {
        guard let sourceId, let mangaId, let chapterId, let word else { return nil }
        return .init(
            chapterId: .init(sourceKey: sourceId, mangaKey: mangaId, chapterKey: chapterId),
            word: word,
            reading: reading,
            sentence: sentence,
            localImageId: localImageId,
            page: Int(page),
            createdDate: createdDate ?? .distantPast
        )
    }

    func load(from entry: VocabEntry) {
        sourceId = entry.chapterId.sourceKey
        mangaId = entry.chapterId.mangaKey
        chapterId = entry.chapterId.chapterKey
        word = entry.word
        reading = entry.reading
        sentence = entry.sentence
        localImageId = entry.localImageId
        page = entry.page.flatMap(Int16.init) ?? 0
        createdDate = entry.createdDate
    }
}
