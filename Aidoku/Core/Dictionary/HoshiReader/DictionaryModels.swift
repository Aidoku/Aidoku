//
//  DictionaryModels.swift
//  Aidoku
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/89feebd40d1df87240f9f587717eab5762dbbd85/Models/Dictionary.swift
//  Modified for use in Aidoku
//

import Foundation

enum DictionaryCategory: String, Codable, CaseIterable, Identifiable {
    case none, monolingual, bilingual, exclude

    var id: String { self.rawValue }
    var label: String {
        switch self {
            case .none: return "None"
            case .monolingual: return "Monolingual"
            case .bilingual: return "Bilingual"
            case .exclude: return "Exclude"
        }
    }
}

struct DictionaryInfo: Identifiable, Codable {
    let id: UUID
    let index: DictionaryIndex
    let path: URL
    var isEnabled: Bool
    var order: Int
    var category: DictionaryCategory

    init(id: UUID = UUID(), index: DictionaryIndex, path: URL, isEnabled: Bool = true, order: Int = 0, category: DictionaryCategory = .none) {
        self.id = id
        self.index = index
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
        self.category = category
    }
}

struct DictionaryConfig: Codable {
    var termDictionaries: [DictionaryEntry]
    var frequencyDictionaries: [DictionaryEntry]
    var pitchDictionaries: [DictionaryEntry]
    var kanjiDictionaries: [DictionaryEntry]?

    struct DictionaryEntry: Codable {
        let fileName: String
        var isEnabled: Bool
        var order: Int
        var category: DictionaryCategory?
    }
}

struct DictionarySummaryCounts: Codable {
    struct ItemCount: Codable {
        let total: Int
    }
    let terms: ItemCount
    let termMeta: [String: Int]
    let kanji: ItemCount
    let kanjiMeta: [String: Int]
    let tagMeta: ItemCount
    let media: ItemCount
}

nonisolated struct DictionaryIndex: Codable {
    let title: String
    let revision: String
    let importDate: Int?
    let counts: DictionarySummaryCounts?
    let isUpdatable: Bool?
    let indexUrl: String?
    let downloadUrl: String?
    let author: String?
    let url: String?
    let description: String?
    let attribution: String?
    let sourceLanguage: String?
    let targetLanguage: String?
    let frequencyMode: String?
}
