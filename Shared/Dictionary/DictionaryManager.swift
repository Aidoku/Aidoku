//
//  DictionaryManager.swift
//  Aidoku
//
//  Created with reference to Hoshi Reader by Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CHoshiDicts
import CxxStdlib

@available(iOS 18.0, macOS 15.0, *)
@MainActor
class DictionaryManager {
    static let shared = DictionaryManager()

    var termDictionaries: [DictionaryInfo] = []
    var frequencyDictionaries: [DictionaryInfo] = []
    var pitchDictionaries: [DictionaryInfo] = []

    private static let configFileName = "config.json"

    private init() {
        loadDictionaries()
    }

    func loadDictionaries() {
        let storedTermDicts = (try? getDictionariesFromStorage(type: .term)) ?? []
        let storedFreqDicts = (try? getDictionariesFromStorage(type: .frequency)) ?? []
        let storedPitchDicts = (try? getDictionariesFromStorage(type: .pitch)) ?? []

        if let config = try? loadDictionaryConfig() {
            termDictionaries = collectDictionaries(storedDicts: storedTermDicts, configDicts: config.termDictionaries)
            frequencyDictionaries = collectDictionaries(storedDicts: storedFreqDicts, configDicts: config.frequencyDictionaries)
            pitchDictionaries = collectDictionaries(storedDicts: storedPitchDicts, configDicts: config.pitchDictionaries)
        } else {
            termDictionaries = storedTermDicts
            frequencyDictionaries = storedFreqDicts
            pitchDictionaries = storedPitchDicts
        }
        rebuildLookupQuery()
    }

    private func collectDictionaries(
        storedDicts: [DictionaryInfo],
        configDicts: [DictionaryConfig.DictionaryEntry]
    ) -> [DictionaryInfo] {
        var result: [DictionaryInfo] = []

        for configDict in configDicts.sorted(by: { $0.order < $1.order }) {
            if let stored = storedDicts.first(where: { $0.path.lastPathComponent == configDict.fileName }) {
                var dictInfo = stored
                dictInfo.isEnabled = configDict.isEnabled
                dictInfo.order = configDict.order
                result.append(dictInfo)
            }
        }

        let currentResult = Set(result.map { $0.path.lastPathComponent })
        for storedDict in storedDicts where !currentResult.contains(storedDict.path.lastPathComponent) {
            var dictInfo = storedDict
            dictInfo.isEnabled = true
            dictInfo.order = result.count
            result.append(dictInfo)
        }
        return result
    }

    private func getDictionariesFromStorage(type: DictionaryType) throws -> [DictionaryInfo] {
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
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map { DictionaryInfo(name: $0.lastPathComponent, path: $0) }
    }

    private func loadDictionaryConfig() throws -> DictionaryConfig? {
        let configURL = try Self.getDictionariesDirectory()
            .appendingPathComponent(Self.configFileName)

        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return nil
        }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(DictionaryConfig.self, from: data)
    }

    func saveDictionaryConfig() {
        let config = DictionaryConfig(
            termDictionaries: termDictionaries.map {
                .init(fileName: $0.path.lastPathComponent, isEnabled: $0.isEnabled, order: $0.order)
            },
            frequencyDictionaries: frequencyDictionaries.map {
                .init(fileName: $0.path.lastPathComponent, isEnabled: $0.isEnabled, order: $0.order)
            },
            pitchDictionaries: pitchDictionaries.map {
                .init(fileName: $0.path.lastPathComponent, isEnabled: $0.isEnabled, order: $0.order)
            }
        )

        guard let configURL = try? Self.getDictionariesDirectory().appendingPathComponent(Self.configFileName) else { return }

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
            LogManager.logger.error("Failed to save dictionary config: \(error.localizedDescription)")
        }
    }

    struct ImportSummary {
        let imported: [String]
        let failed: [String]

        var didImportAny: Bool {
            !imported.isEmpty
        }
    }

    func importDictionary(from urls: [URL]) async -> ImportSummary {
        guard let dictionariesDir = try? Self.getDictionariesDirectory() else {
            let failed = urls.map(\.lastPathComponent)
            return .init(imported: [], failed: failed)
        }

        return await Task.detached {
            var imported: [String] = []
            var failed: [String] = []

            for url in urls {
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
                    let title = String(cString: importResult.title.__c_strUnsafe())
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(title)
                    defer { try? FileManager.default.removeItem(at: temp) }
                    if importResult.term_count > 0 {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.term.rawValue).appendingPathComponent(title)
                        try? FileManager.default.moveItem(at: temp, to: destination)
                    } else if importResult.freq_count > 0 {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.frequency.rawValue).appendingPathComponent(title)
                        try? FileManager.default.moveItem(at: temp, to: destination)
                    } else if importResult.pitch_count > 0 {
                        let destination = dictionariesDir.appendingPathComponent(DictionaryType.pitch.rawValue).appendingPathComponent(title)
                        try? FileManager.default.moveItem(at: temp, to: destination)
                    }
                    imported.append(current)
                } else {
                    failed.append(current)
                }
            }

            await MainActor.run { [imported] in
                if !imported.isEmpty {
                    self.loadDictionaries()
                    self.saveDictionaryConfig()
                    self.rebuildLookupQuery()
                }
            }

            return .init(imported: imported, failed: failed)
        }.value
    }

    func deleteDictionary(indexSet: IndexSet, type: DictionaryType) {
        switch type {
        case .term:
            for index in indexSet {
                try? FileManager.default.removeItem(at: termDictionaries[index].path)
            }
            termDictionaries.remove(atOffsets: indexSet)
        case .frequency:
            for index in indexSet {
                try? FileManager.default.removeItem(at: frequencyDictionaries[index].path)
            }
            frequencyDictionaries.remove(atOffsets: indexSet)
        case .pitch:
            for index in indexSet {
                try? FileManager.default.removeItem(at: pitchDictionaries[index].path)
            }
            pitchDictionaries.remove(atOffsets: indexSet)
        }
        saveDictionaryConfig()
        rebuildLookupQuery()
    }

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
        }
        saveDictionaryConfig()
        rebuildLookupQuery()
    }

    func rebuildLookupQuery() {
        LookupEngine.shared.buildQuery(
            termPaths: termDictionaries.filter(\.isEnabled).map(\.path),
            freqPaths: frequencyDictionaries.filter(\.isEnabled).map(\.path),
            pitchPaths: pitchDictionaries.filter(\.isEnabled).map(\.path)
        )
    }

    static func getDictionariesDirectory() throws -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("Dictionaries")
    }
}
