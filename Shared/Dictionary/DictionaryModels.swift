//
//  DictionaryModels.swift
//  Aidoku
//
//  Created with reference to Hoshi Reader by Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct DictionaryInfo: Identifiable, Codable {
    let id: UUID
    let name: String
    let path: URL
    var isEnabled: Bool
    var order: Int

    init(id: UUID = UUID(), name: String, path: URL, isEnabled: Bool = true, order: Int = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.order = order
    }
}

struct DictionaryConfig: Codable {
    var termDictionaries: [DictionaryEntry]
    var frequencyDictionaries: [DictionaryEntry]
    var pitchDictionaries: [DictionaryEntry]

    struct DictionaryEntry: Codable {
        let fileName: String
        var isEnabled: Bool
        var order: Int
    }
}

enum DictionaryType: String {
    case term = "Term"
    case frequency = "Frequency"
    case pitch = "Pitch"
}

struct DictGlossaryData: Encodable {
    let dictionary: String
    let content: String
    let definitionTags: String
    let termTags: String
}

struct DictFrequencyData: Encodable {
    let dictionary: String
    let frequencies: [DictFrequencyTag]
}

struct DictFrequencyTag: Encodable {
    let value: Int
    let displayValue: String
}

struct DictPitchData: Encodable {
    let dictionary: String
    let pitchPositions: [Int]
}

struct DictEntryData: Encodable {
    let expression: String
    let reading: String
    let matched: String
    let deinflectionTrace: [DictDeinflectionTag]
    let glossaries: [DictGlossaryData]
    let frequencies: [DictFrequencyData]
    let pitches: [DictPitchData]
    let definitionTags: [String]
}

struct DictDeinflectionTag: Encodable {
    let name: String
    let description: String
}
