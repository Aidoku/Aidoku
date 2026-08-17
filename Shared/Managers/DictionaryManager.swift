//
//  DictionaryManager.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/c31c9d0ce376ff83bf6a91d908bf9f8e0fb4947b/Core/DictionaryManager.swift
//  Modified for use in Aidoku
//

import Foundation
import SwiftUI
import CHoshiDicts
import CxxStdlib

enum DictionaryType: String {
    case term = "Term"
    case frequency = "Frequency"
    case pitch = "Pitch"
    case kanji = "Kanji"
}

@available(iOS 18.0, macOS 15.0, *)
@Observable
@MainActor
class DictionaryManager {
    static let shared = DictionaryManager()

    private(set) var termDictionaries: [DictionaryInfo] = []
    private(set) var frequencyDictionaries: [DictionaryInfo] = []
    private(set) var pitchDictionaries: [DictionaryInfo] = []
    private(set) var kanjiDictionaries: [DictionaryInfo] = []
    private(set) var updatableDictionaries: [(DictionaryInfo, DictionaryType)] = []
    //    private(set) var collapsedDictionaries: Set<String> = []
    private(set) var isImporting = false
    private(set) var isUpdating = false
    var shouldShowError = false
    var errorMessage = ""
    var currentImport = ""

    var excludedDictionaries: [String] {
        termDictionaries.filter { $0.category == .exclude }.map { $0.index.title }
    }

    private static let configFileName = "config.json"
    //    private static let collapsedConfig = "collapsed.json"

    private init() {
        loadDictionaries()
        //        loadCollapsedDictionaries()
        rebuildLookupQuery()
    }

    func loadDictionaries() {
        updatableDictionaries = []
        let storedTermDicts = (try? getDictionariesFromStorage(type: .term)) ?? []
        let storedFreqDicts = (try? getDictionariesFromStorage(type: .frequency)) ?? []
        let storedPitchDicts = (try? getDictionariesFromStorage(type: .pitch)) ?? []
        let storedKanjiDicts = (try? getDictionariesFromStorage(type: .kanji)) ?? []

        if let config = try? loadDictionaryConfig() {
            termDictionaries = collectDictionaries(storedDicts: storedTermDicts, configDicts: config.termDictionaries)
            frequencyDictionaries = collectDictionaries(storedDicts: storedFreqDicts, configDicts: config.frequencyDictionaries)
            pitchDictionaries = collectDictionaries(storedDicts: storedPitchDicts, configDicts: config.pitchDictionaries)
            kanjiDictionaries = collectDictionaries(storedDicts: storedKanjiDicts, configDicts: config.kanjiDictionaries ?? [])
        } else {
            termDictionaries = storedTermDicts
            frequencyDictionaries = storedFreqDicts
            pitchDictionaries = storedPitchDicts
            kanjiDictionaries = storedKanjiDicts
        }
    }

    func rebuildLookupQuery() {
        let enabledTermPaths = termDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }

        let enabledFreqPaths = frequencyDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }

        let enabledPitchPaths = pitchDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }

        let enabledKanjiPaths = kanjiDictionaries
            .filter { $0.isEnabled }
            .map { $0.path }

        LookupEngine.shared.buildQuery(
            termPaths: enabledTermPaths,
            freqPaths: enabledFreqPaths,
            pitchPaths: enabledPitchPaths,
            kanjiPaths: enabledKanjiPaths
        )
    }

    func collectDictionaries(storedDicts: [DictionaryInfo], configDicts: [DictionaryConfig.DictionaryEntry]) -> [DictionaryInfo] {
        var result: [DictionaryInfo] = []

        // collect dictionaries that are saved in config
        for configDict in configDicts.sorted(by: { $0.order < $1.order }) {
            if let stored = storedDicts.first(where: { $0.path.lastPathComponent == configDict.fileName }) {
                var dictInfo = stored
                dictInfo.isEnabled = configDict.isEnabled
                dictInfo.order = configDict.order
                dictInfo.category = configDict.category ?? .none
                result.append(dictInfo)
            }
        }

        // append remaining dicts that were imported
        let currentResult = Set(result.map({ $0.path.lastPathComponent }))
        for storedDict in storedDicts where !currentResult.contains(storedDict.path.lastPathComponent) {
            var dictInfo = storedDict
            dictInfo.isEnabled = true
            dictInfo.order = result.count
            result.append(dictInfo)
        }
        return result
    }

    func getDictionariesFromStorage(type: DictionaryType) throws -> [DictionaryInfo] {
        let directory = try Self.getDictionariesDirectory()
            .appendingPathComponent(type.rawValue)

        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap {
            let values = try $0.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                try? FileManager.default.removeItem(at: $0)
                return nil
            }
            guard
                case let url = $0.appendingPathComponent("index.json"),
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                let data = try? Data(contentsOf: url),
                let index = try? JSONDecoder().decode(DictionaryIndex.self, from: data)
                    else {
                try? FileManager.default.removeItem(at: $0)
                return nil
            }
            let result = DictionaryInfo(index: index, path: $0)
            if index.isUpdatable == true && !(index.indexUrl ?? "").isEmpty && !(index.downloadUrl ?? "").isEmpty {
                updatableDictionaries.append((result, type))
            }
            return result
        }
    }

    private func loadDictionaryConfig() throws -> DictionaryConfig? {
        let configURL = try Self.getDictionariesDirectory()
            .appendingPathComponent(Self.configFileName)

        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            return try decoder.decode(DictionaryConfig.self, from: data)
        }
        return nil
    }

    //    private func loadCollapsedDictionaries() {
    //        do {
    //            let configURL = try Self.getDictionariesDirectory()
    //                .appendingPathComponent(Self.collapsedConfig)
    //
    //            if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
    //                let data = try Data(contentsOf: configURL)
    //                let decoder = JSONDecoder()
    //                collapsedDictionaries = try decoder.decode(Set<String>.self, from: data)
    //            }
    //        } catch {
    //            collapsedDictionaries = []
    //        }
    //    }

    private func saveDictionaryConfig() {
        let config = DictionaryConfig(
            termDictionaries: termDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order,
                    category: $0.category
                )
            },
            frequencyDictionaries: frequencyDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order,
                    category: $0.category
                )
            },
            pitchDictionaries: pitchDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order,
                    category: $0.category
                )
            },
            kanjiDictionaries: kanjiDictionaries.map {
                DictionaryConfig.DictionaryEntry(
                    fileName: $0.path.lastPathComponent,
                    isEnabled: $0.isEnabled,
                    order: $0.order,
                    category: $0.category
                )
            }
        )

        guard let configURL = try? Self.getDictionariesDirectory()
            .appendingPathComponent(Self.configFileName) else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)

            let directory = configURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            try data.write(to: configURL, options: .atomic)
        } catch {
            showError("Failed to save dictionary config: \(error.localizedDescription)")
        }
    }

    //    func saveCollapsedDictionaries() {
    //        guard let configURL = try? Self.getDictionariesDirectory()
    //            .appendingPathComponent(Self.collapsedConfig) else {
    //            return
    //        }
    //
    //        do {
    //            let encoder = JSONEncoder()
    //            encoder.outputFormatting = .prettyPrinted
    //            let data = try encoder.encode(collapsedDictionaries)
    //
    //            let directory = configURL.deletingLastPathComponent()
    //            if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
    //                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    //            }
    //
    //            try data.write(to: configURL, options: .atomic)
    //        } catch {
    //            showError("Failed to save collapsed dictionaries: \(error.localizedDescription)")
    //        }
    //    }

    func importDictionary(from urls: [URL]) async {
        guard let dictionariesDir = try? Self.getDictionariesDirectory() else { return }

        isImporting = true

        Task.detached {
            var imported: [String] = []
            var failed: [String] = []

            for url in urls {
                await MainActor.run {
                    self.currentImport = "Importing \(url.lastPathComponent)"
                }

                let current = url.lastPathComponent
                let secured = url.startAccessingSecurityScopedResource()
                defer {
                    if secured {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let importResult = dictionary_importer.import(
                    std.string(url.path(percentEncoded: false)),
                    std.string(FileManager.default.temporaryDirectory.path(percentEncoded: false))
                )

                if importResult.success {
                    let title = String(importResult.title)
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(String(title))
                    defer { try? FileManager.default.removeItem(at: temp) }

                    let counts = importResult.summary.counts
                    if counts.terms.total > 0 {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.term.rawValue).appendingPathComponent(title)
                        try? FileManager.default.copyItem(at: temp, to: destination)
                    }
                    if counts.termMeta[std.string("freq")] != nil {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.frequency.rawValue).appendingPathComponent(title)
                        try? FileManager.default.copyItem(at: temp, to: destination)
                    }
                    if counts.termMeta[std.string("pitch")] != nil || counts.termMeta[std.string("ipa")] != nil {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.pitch.rawValue).appendingPathComponent(title)
                        try? FileManager.default.copyItem(at: temp, to: destination)
                    }
                    if counts.kanji.total > 0 {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.kanji.rawValue).appendingPathComponent(title)
                        try? FileManager.default.copyItem(at: temp, to: destination)
                    }
                    imported.append(current)
                } else {
                    failed.append(current)
                }
            }

            await MainActor.run { [imported, failed] in
                self.isImporting = false

                if !imported.isEmpty {
                    self.loadDictionaries()
                    self.saveDictionaryConfig()
                    self.rebuildLookupQuery()
                }

                if imported.isEmpty {
                    self.showError("failed to import dictionary")
                } else if !failed.isEmpty {
                    self.showError("some dictionaries could not be imported:\n\(failed.joined(separator: "\n"))")
                }
            }
        }
    }

    func updateDictionaries(showErrors: Bool = true, session: URLSession = .shared) {
        let dictionaries = updatableDictionaries
        isUpdating = true
        Task.detached {
            var failures: [String] = []
            for (dictionary, type) in dictionaries {
                let index = dictionary.index
                await MainActor.run {
                    self.currentImport = "Checking \(index.title)"
                }

                do {
                    guard
                        let indexUrl = index.indexUrl,
                        let importResult = try await self.importRemoteDictionary(
                            indexUrl: indexUrl,
                            type: type,
                            session: session
                        )
                            else { continue }

                    let new = String(importResult.title)
                    let old = dictionary.index.title

                    await MainActor.run {
                        self.loadDictionaries()
                        if old != new {
                            if let currentIndex = self.getDictionaryIndex(title: old, type: type) {
                                let wasEnabled = self.isDictionaryEnabled(at: currentIndex, type: type)
                                //                                let wasCollapsed = self.collapsedDictionaries.contains(old)
                                let wasCategory = type == .term ? self.termDictionaries[currentIndex].category : .none
                                self.deleteDictionary(indexSet: IndexSet(integer: currentIndex), type: type)
                                let importedIndex = self.getDictionaryIndex(title: new, type: type)!
                                self.setDictionaryEnabled(index: importedIndex, enabled: wasEnabled, type: type)
                                let newId = type == .term ? self.termDictionaries[importedIndex].id : nil
                                self.moveDictionary(from: IndexSet(integer: importedIndex), to: currentIndex, type: type)
                                if let newId, wasCategory != .none {
                                    self.setDictionaryCategory(id: newId, category: wasCategory)
                                }
                                //                                AnkiManager.shared.updateHandlebar(old: old, new: new)
                                //                                if wasCollapsed {
                                //                                    self.collapsedDictionaries.insert(new)
                                //                                    self.saveCollapsedDictionaries()
                                //                                }
                            }
                        } else {
                            self.rebuildLookupQuery()
                        }
                    }
                } catch {
                    failures.append("\(index.title): \(error.localizedDescription)")
                }
            }

            await MainActor.run { [failures] in
                self.isUpdating = false
                if failures.count < dictionaries.count {
                    AppSettings.dictionary.lastUpdate.set(Date.now)
                }
                if !failures.isEmpty && showErrors {
                    self.showError(failures.joined(separator: "\n"))
                }
            }
        }
    }

    func downloadDictionary(indexUrl: String, type: DictionaryType) async -> Bool {
        isImporting = true

        return await Task.detached {
            var failure: String?

            do {
                _ = try await self.importRemoteDictionary(indexUrl: indexUrl, type: type)
            } catch {
                failure = error.localizedDescription
            }

            await MainActor.run { [failure] in
                self.isImporting = false

                if let failure {
                    self.showError(failure)
                } else {
                    self.loadDictionaries()
                    self.saveDictionaryConfig()
                    self.rebuildLookupQuery()
                }
            }

            return failure == nil
        }.value
    }

    private nonisolated func importRemoteDictionary(
        indexUrl: String,
        type: DictionaryType,
        session: URLSession = .shared
    ) async throws -> ImportResult? {
        let existingIndex: DictionaryIndex? = await Task { @MainActor in
            let targetDictionaries = switch type {
                case .term: termDictionaries
                case .frequency: frequencyDictionaries
                case .pitch: pitchDictionaries
                case .kanji: kanjiDictionaries
            }
            return targetDictionaries.first(where: { $0.index.indexUrl == indexUrl })?.index
        }.value

        let (data, _) = try await session.data(from: URL(string: indexUrl)!)
        let remoteIndex = try JSONDecoder().decode(DictionaryIndex.self, from: data)

        if existingIndex?.revision == remoteIndex.revision {
            return nil
        }

        await MainActor.run {
            self.currentImport = "Downloading \(remoteIndex.title)"
        }

        var tempFiles: [URL] = []
        defer {
            for file in tempFiles {
                try? FileManager.default.removeItem(at: file)
            }
        }

        guard let downloadUrl = remoteIndex.downloadUrl else { return nil }

        let (temp, _) = try await session.download(from: URL(string: downloadUrl)!)
        tempFiles.append(temp)

        await MainActor.run {
            self.currentImport = "Importing \(remoteIndex.title)"
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFiles.append(tempDir)

        let importResult = dictionary_importer.import(
            std.string(temp.path(percentEncoded: false)),
            std.string(tempDir.path(percentEncoded: false))
        )

        if !importResult.success {
            throw NSError(domain: Bundle.main.bundleIdentifier ?? "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Import failed"])
        }

        let new = String(importResult.title)
        let old = existingIndex?.title
        let tempPath = tempDir.appendingPathComponent(new)
        let destPath = try await Self.getDictionariesDirectory()
            .appendingPathComponent(type.rawValue)
            .appendingPathComponent(new)

        if new == old {
            try? FileManager.default.removeItem(at: destPath)
        }
        try FileManager.default.moveItem(at: tempPath, to: destPath)

        return importResult
    }

    func autoUpdateDictionaries() {
        guard !isImporting, !isUpdating, !updatableDictionaries.isEmpty else { return }

        let interval = AppSettings.dictionary.updateInterval.get().timeInterval
        guard interval > 0 else { return }

        let lastUpdate = AppSettings.dictionary.lastUpdate.get()
        guard Date.now.timeIntervalSince(lastUpdate) >= interval else { return }

        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        updateDictionaries(showErrors: false, session: URLSession(configuration: config))
    }
}

@available(iOS 18.0, *)
extension DictionaryManager {
    func toggleDictionary(id: UUID, enabled: Bool, type: DictionaryType) {
        switch type {
            case .term:
                guard let index = termDictionaries.firstIndex(where: { $0.id == id }) else { return }
                termDictionaries[index].isEnabled = enabled
            case .frequency:
                guard let index = frequencyDictionaries.firstIndex(where: { $0.id == id }) else { return }
                frequencyDictionaries[index].isEnabled = enabled
            case .pitch:
                guard let index = pitchDictionaries.firstIndex(where: { $0.id == id }) else { return }
                pitchDictionaries[index].isEnabled = enabled
            case .kanji:
                guard let index = kanjiDictionaries.firstIndex(where: { $0.id == id }) else { return }
                kanjiDictionaries[index].isEnabled = enabled
        }
        saveDictionaryConfig()
        rebuildLookupQuery()
    }

    func setDictionaryCategory(id: UUID, category: DictionaryCategory) {
        guard let index = termDictionaries.firstIndex(where: { $0.id == id }) else { return }
        termDictionaries[index].category = category
        saveDictionaryConfig()
    }

    func moveDictionary(from: IndexSet, to: Int, type: DictionaryType) {
        switch type {
            case .term:
                termDictionaries.move(fromOffsets: from, toOffset: to)
            case .frequency:
                frequencyDictionaries.move(fromOffsets: from, toOffset: to)
            case .pitch:
                pitchDictionaries.move(fromOffsets: from, toOffset: to)
            case .kanji:
                kanjiDictionaries.move(fromOffsets: from, toOffset: to)
        }
        updateOrder(type: type)
        saveDictionaryConfig()
        rebuildLookupQuery()
    }

    func updateOrder(type: DictionaryType) {
        switch type {
            case .term:
                for index in termDictionaries.indices {
                    termDictionaries[index].order = index
                }
            case .frequency:
                for index in frequencyDictionaries.indices {
                    frequencyDictionaries[index].order = index
                }
            case .pitch:
                for index in pitchDictionaries.indices {
                    pitchDictionaries[index].order = index
                }
            case .kanji:
                for index in kanjiDictionaries.indices {
                    kanjiDictionaries[index].order = index
                }
        }
    }

    func deleteDictionary(indexSet: IndexSet, type: DictionaryType) {
        switch type {
            case .term:
                for index in indexSet {
                    let dictionary = termDictionaries[index]
                    try? FileManager.default.removeItem(at: dictionary.path)
                    termDictionaries.remove(at: index)
                    updatableDictionaries.removeAll { $0.0.index.title == dictionary.index.title }
                }
            case .frequency:
                for index in indexSet {
                    let dictionary = frequencyDictionaries[index]
                    try? FileManager.default.removeItem(at: dictionary.path)
                    frequencyDictionaries.remove(at: index)
                    updatableDictionaries.removeAll { $0.0.index.title == dictionary.index.title }
                }
            case .pitch:
                for index in indexSet {
                    let dictionary = pitchDictionaries[index]
                    try? FileManager.default.removeItem(at: dictionary.path)
                    pitchDictionaries.remove(at: index)
                    updatableDictionaries.removeAll { $0.0.index.title == dictionary.index.title }
                }
            case .kanji:
                for index in indexSet {
                    let dictionary = kanjiDictionaries[index]
                    try? FileManager.default.removeItem(at: dictionary.path)
                    kanjiDictionaries.remove(at: index)
                    updatableDictionaries.removeAll { $0.0.index.title == dictionary.index.title }
                }
        }
        updateOrder(type: type)
        saveDictionaryConfig()
//        saveCollapsedDictionaries()
        rebuildLookupQuery()
    }

//    func toggleCollapsedDictionary(title: String) {
//        if collapsedDictionaries.contains(title) {
//            collapsedDictionaries.remove(title)
//        } else {
//            collapsedDictionaries.insert(title)
//        }
//        saveCollapsedDictionaries()
//    }

    private func isDictionaryEnabled(at index: Int, type: DictionaryType) -> Bool {
        switch type {
            case .term:
                termDictionaries[index].isEnabled
            case .frequency:
                frequencyDictionaries[index].isEnabled
            case .pitch:
                pitchDictionaries[index].isEnabled
            case .kanji:
                kanjiDictionaries[index].isEnabled
        }
    }

    private func setDictionaryEnabled(index: Int, enabled: Bool, type: DictionaryType) {
        switch type {
            case .term:
                termDictionaries[index].isEnabled = enabled
            case .frequency:
                frequencyDictionaries[index].isEnabled = enabled
            case .pitch:
                pitchDictionaries[index].isEnabled = enabled
            case .kanji:
                kanjiDictionaries[index].isEnabled = enabled
        }
    }

    private func getDictionaryIndex(title: String, type: DictionaryType) -> Int? {
        switch type {
            case .term:
                termDictionaries.firstIndex { $0.index.title == title }
            case .frequency:
                frequencyDictionaries.firstIndex { $0.index.title == title }
            case .pitch:
                pitchDictionaries.firstIndex { $0.index.title == title }
            case .kanji:
                kanjiDictionaries.firstIndex { $0.index.title == title }
        }
    }

    private static func getDictionariesDirectory() throws -> URL {
        FileManager.default.documentDirectory.appendingPathComponent("Dictionaries")
    }

    private func showError(_ message: String) {
        errorMessage = message
        shouldShowError = true
    }
}
