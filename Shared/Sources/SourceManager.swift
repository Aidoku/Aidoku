//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import ZIPFoundation

class SourceManager {

    static let shared = SourceManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true)

    var sources: [Source] = []
    var sourceLists: [URL] = []

    var languageCodes = [
        "multi", "en", "ca", "de", "es", "fr", "id", "it", "pl", "pt-br", "vi", "tr", "ru", "ar", "zh", "zh-hans", "ja", "ko"
    ]

    private var sourceListsStrings: [String] {
        sourceLists.map { $0.absoluteString }
    }

    init() {
        sources = (try? DataManager.shared.getSourceObjects())?.compactMap { $0.toSource() } ?? []
        sources.sort { $0.manifest.info.name < $1.manifest.info.name }
        sources.sort { languageCodes.firstIndex(of: $0.manifest.info.lang) ?? 0 < languageCodes.firstIndex(of: $1.manifest.info.lang) ?? 0 }
        sourceLists = (UserDefaults.standard.array(forKey: "Browse.sourceLists") as? [String] ?? []).compactMap { URL(string: $0) }

        Task {
            for source in sources {
                _ = try? await source.getFilters()
            }
            NotificationCenter.default.post(name: Notification.Name("loadedSourceFilters"), object: nil)
        }
    }
}

// MARK: - Source Management
extension SourceManager {

    func source(for id: String) -> Source? {
        sources.first { $0.id == id }
    }

    func hasSourceInstalled(id: String) -> Bool {
        sources.contains { $0.id == id }
    }

    func importSource(from url: URL) async -> Source? {
        Self.directory.createDirectory()

        var fileUrl = url

        if let temporaryDirectory = FileManager.default.temporaryDirectory {
            if fileUrl.scheme != "file" {
                do {
                    let location = try await URLSession.shared.download(for: URLRequest.from(url))
                    fileUrl = location
                } catch {
                    return nil
                }
            }
            try? FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
            try? FileManager.default.removeItem(at: fileUrl)

            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try? Source(from: payload)
            if let source = source {
                let destination = Self.directory.appendingPathComponent(source.id)
                if destination.exists {
                    try? FileManager.default.removeItem(at: destination)
                    sources.removeAll { $0.id == source.id }
                }
                try? FileManager.default.moveItem(at: payload, to: destination)
                try? FileManager.default.removeItem(at: temporaryDirectory)

                source.url = destination

                await DataManager.shared.add(source: source, context: DataManager.shared.backgroundContext)
                sources.append(source)
                sources.sort { $0.manifest.info.name < $1.manifest.info.name }
                sources.sort { languageCodes.firstIndex(of: $0.manifest.info.lang) ?? 0 < languageCodes.firstIndex(of: $1.manifest.info.lang) ?? 0 }

                NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

                Task {
                    _ = try? await source.getFilters()
                }

                return source
            }
        }

        return nil
    }

    func clearSources() {
        for source in sources {
            try? FileManager.default.removeItem(at: source.url)
        }
        sources = []
        DataManager.shared.clearSources()
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }

    func remove(source: Source) {
        try? FileManager.default.removeItem(at: source.url)
        DataManager.shared.delete(source: source)
        sources.removeAll { $0.id == source.id }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
}

// MARK: - Source List Management
extension SourceManager {

    func addSourceList(url: URL) async -> Bool {
        guard !sourceLists.contains(url) else { return false }

        if (try? await URLSession.shared.object(
            from: url.appendingPathComponent("index.min.json")
        ) as [ExternalSourceInfo]?) == nil {
            return false
        }

        sourceLists.append(url)
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
        return true
    }

    func removeSourceList(url: URL) {
        sourceLists.removeAll { $0 == url }
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
    }

    func clearSourceLists() {
        sourceLists = []
        UserDefaults.standard.set([], forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: Notification.Name("updateSourceLists"), object: nil)
    }
}
