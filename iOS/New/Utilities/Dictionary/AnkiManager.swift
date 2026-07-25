//
//  AnkiManager.swift
//  Aidoku
//
//  Created by skitty on 7/20/26.
//

import SwiftUI

// AnkiManager shim for Hoshi Reader code to interface with Aidoku's VocabManager

struct AnkiCardFormat: Codable, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    var selectedDeck: String?
    var selectedNoteType: String?
    var fieldMappings: [String: String]
    var tags: String

    static let icons = ["plus.square", "plus.square.small", "plus.circle", "plus.circle.small", "plus.diamond", "plus.diamond.small"]
    static let duplicateIcons: [String: String] = [
        "plus.square": "plus.square.on.square",
        "plus.circle": "plus.circle.fill",
        "plus.diamond": "plus.diamond.fill"
    ]
}

struct MiningContext {
    let sentence: String
    let chapterId: ChapterIdentifier
    let page: Int
//    var clozeOffset: Int?
//    let documentTitle: String?
//    let coverURL: URL?
//    var sasayakiAudioData: Data?
}

class AnkiManager {
    static let shared = AnkiManager()

    let cardFormats: [AnkiCardFormat] = [.init(id: UUID(), name: "", icon: AnkiCardFormat.icons[0], fieldMappings: [:], tags: "")]

    static let wordAddedNotification = Notification.Name("hoshiWordAdded")

    func checkDuplicates(fields: [String: String]) async -> [Bool] {
        guard let expression = fields["{expression}"] else { return [false] }
        let reading = fields["{reading}"]
        return [await VocabManager.shared.has(word: expression, reading: reading)]
    }

    func showNotes(fields: [String: String], formatIndex: Int) async {
        guard
            #available(iOS 18.0, *),
            let presentationController = await (UIApplication.shared.delegate as? AppDelegate)?.topViewController,
            let expression = fields["{expression}"],
            let entry = await VocabManager.shared.get(word: expression, reading: fields["{reading}"])
        else {
            return
        }
        await MainActor.run {
            let viewController = UIHostingController(rootView: DictionaryVocabDetailsView(entry: entry))
            presentationController.present(viewController, animated: true)
        }
    }

    func addNote(content: [String: String], context: MiningContext, formatId: UUID) async -> Bool {
        guard let expression = content["expression"] else { return false }
        let reading = content["reading"]
        await VocabManager.shared.create(
            entry: .init(
                chapterId: context.chapterId,
                word: expression,
                reading: reading,
                sentence: context.sentence,
                page: context.page
            )
        )
        return true
    }
}
