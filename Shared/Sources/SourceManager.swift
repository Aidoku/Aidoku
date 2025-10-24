//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import AidokuRunner
import Foundation
import ZIPFoundation

#if canImport(UIKit)
import UIKit
#endif

class SourceManager {
    static let shared = SourceManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true)

    var sources: [AidokuRunner.Source] = []
    var sourceLists: [SourceList] = []
    var sourceListURLs: [URL]
    var sourceListLanguages: Set<String> = []

    private var loadSourcesTask: Task<(), Never>?
    private var loadSourceListsTask: Task<(), Never>?

    static let languageCodes = [
        "multi", "en", "ca", "de", "es", "fr", "id", "it", "pl", "pt-br", "vi", "tr", "ru", "ar", "zh", "zh-hans", "ja", "ko"
    ]

    var sourceListsStrings: [String] {
        sourceListURLs.map { $0.absoluteString }
    }

    var localSourceInstalled: Bool {
        sources.contains(where: { $0.id == LocalSourceRunner.sourceKey })
    }

    init() {
        sourceListURLs = (UserDefaults.standard.array(forKey: "Browse.sourceLists") as? [String] ?? [])
            .compactMap { URL(string: $0) }

        loadSourcesTask = Task {
            // load installed sources
            sources = await getInstalledSources()
            sortSources()
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

            // load source filters
            await withTaskGroup(of: Void.self) { group in
                for source in sources {
                    if let legacySource = source.legacySource {
                        group.addTask {
                            _ = try? await legacySource.getFilters()
                        }
                    }
                }
            }
            NotificationCenter.default.post(name: Notification.Name("loadedSourceFilters"), object: nil)
        }

        Task {
            await loadSourceLists(reload: true)
        }
    }

    func loadSources() async {
        await loadSourcesTask?.value
    }

    func loadSourceLists(reload: Bool = false) async {
        if let loadSourceListsTask {
            await loadSourceListsTask.value
            self.loadSourceListsTask = nil
        }
        if reload {
            loadSourceListsTask = Task {
                sourceLists = await withTaskGroup(of: SourceList?.self) { group in
                    for url in sourceListURLs {
                        // load sources from list
                        group.addTask {
                            await self.loadSourceList(url: url)
                        }
                    }
                    var results: [SourceList] = []
                    for await result in group {
                        guard let result else { continue }
                        results.append(result)
                    }
                    return results
                }
                loadSourceListLanguages()
                NotificationCenter.default.post(name: .updateSourceLists, object: nil)
            }
            await loadSourceListsTask?.value
        }
    }

    func getInstalledSources() async -> [AidokuRunner.Source] {
        let objects: [SourceObjectData] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSources(context: context).map { $0.toData() }
        }
        var sources: [AidokuRunner.Source] = []
        for dbSource in objects {
            if let source = await dbSource.toNewSource() {
                if sources.contains(where: { $0.id == source.id }) {
                    // remove duplicate coredata sources
                    CoreDataManager.shared.remove(dbSource.objectID)
                } else {
                    sources.append(source)
                }
            }
        }
        return sources
    }
}

// MARK: - Source Management
extension SourceManager {

    func source(for id: String) -> AidokuRunner.Source? {
        sources.first { $0.id == id }
    }

    func hasSourceInstalled(id: String) -> Bool {
        sources.contains { $0.id == id }
    }

    func importSource(from url: URL) async throws -> AidokuRunner.Source? {
        Self.directory.createDirectory()

        var fileUrl = url

        guard let temporaryDirectory = FileManager.default.temporaryDirectory
        else { return nil }
        if fileUrl.scheme != "file" {
            do {
                let location = try await URLSession.shared.download(for: URLRequest.from(url))
                fileUrl = location
            } catch {
                return nil
            }
        }
        try FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)

        let payload = temporaryDirectory.appendingPathComponent("Payload")
        var newSource = try? await AidokuRunner.Source(url: payload)
        let legacySource: Source?
        if newSource == nil {
            legacySource = try? Source(from: payload)
        } else {
            legacySource = nil
        }

        let id: String
        if let newSource {
            id = newSource.id
        } else if let legacySource {
            id = legacySource.id
        } else {
            return nil
        }

        let destination = Self.directory.appendingPathComponent(id)
        if destination.exists {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: payload, to: destination)
        try? FileManager.default.removeItem(at: temporaryDirectory)

        if newSource != nil {
            newSource = try? await AidokuRunner.Source(id: id, url: destination)
        } else if let legacySource {
            legacySource.url = destination
        }

        let installedSource = sources
            .firstIndex { $0.id == id }
            .flatMap { sources.remove(at: $0) }
        if installedSource != nil {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeSource(id: id, context: context)
                try? context.save()
            }
        }

        let result: AidokuRunner.Source

        if let newSource {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.createSource(source: newSource, context: context)
                try? context.save()
            }

            if
                let installedVersion = installedSource?.version,
                let breakingChangeVersion = newSource.config?.breakingChangeVersion,
                installedVersion < breakingChangeVersion
            {
                // if there was a breaking change, prompt for migration
#if !os(macOS)
                Task { @MainActor in
                    (UIApplication.shared.delegate as? AppDelegate)?.handleSourceMigration(source: newSource)
                }
#endif
            }

            result = newSource
        } else if let legacySource {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.createSource(source: legacySource, context: context)
                try? context.save()
            }

            Task {
                _ = try? await legacySource.getFilters()
            }

            result = .legacy(source: legacySource)
        } else {
            return nil
        }

        sources.append(result)
        sortSources()

        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

        return result
    }

    enum CustomSourceKind {
        case komga
        case kavita
    }

    @discardableResult
    func createCustomSource(
        kind: CustomSourceKind,
        name: String,
        server: String,
        username: String? = nil,
        password: String? = nil,
    ) async -> String {
        let keyPrefix = switch kind {
            case .komga: "komga."
            case .kavita: "kavita."
        }
        let nameEncoded = name.lowercased().replacingOccurrences(of: " ", with: "-")
        var key = "\(keyPrefix)\(nameEncoded)"

        // make sure key is unique
        var counter = 1
        while SourceManager.shared.hasSourceInstalled(id: key) {
            key = "\(keyPrefix)\(nameEncoded)-\(counter)"
            counter += 1
        }

        let config = switch kind {
            case .komga: CustomSourceConfig.komga(key: key, name: name, server: server)
            case .kavita: CustomSourceConfig.kavita(key: key, name: name, server: server)
        }
        let source = config.toSource()

        // add to coredata
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let result = CoreDataManager.shared.createSource(source: source, context: context)
            result.customSource = config.encode() as NSObject
            try? context.save()
        }

        // register details
        UserDefaults.standard.setValue(server, forKey: "\(key).server")
        if username != nil || password != nil {
            UserDefaults.standard.setValue("logged_in", forKey: "\(key).login")
        }
        if let username {
            UserDefaults.standard.setValue(username, forKey: "\(key).login.username")
        }
        if let password {
            UserDefaults.standard.setValue(password, forKey: "\(key).login.password")
        }

        sources.append(source)
        sortSources()

        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)

        return key
    }

    func sortSources() {
        sources.sort { $0.name < $1.name }
        sources.sort {
            let lhs = Self.languageCodes.firstIndex(of: $0.languages.count == 1 ? $0.languages[0] : "multi") ?? Int.max
            let rhs = Self.languageCodes.firstIndex(of: $1.languages.count == 1 ? $1.languages[0] : "multi") ?? Int.max
            return lhs < rhs
        }
    }

    func clearSources() {
        for source in sources {
            guard let url = source.url else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        sources = []
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.clearSources(context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
        }
    }

    func remove(source: AidokuRunner.Source) {
        if let url = source.url {
            try? FileManager.default.removeItem(at: url)
        }
        sources.removeAll { $0.id == source.id }
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeSource(id: source.id, context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
        }
    }

    // Pin a source in browse tab.
    func pin(source: AidokuRunner.Source) {
        let key = "Browse.pinnedList"
        var pinnedList = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !pinnedList.contains(source.id) {
            pinnedList.append(source.id)
            UserDefaults.standard.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }

    // Unpin a source in browse tab.
    func unpin(source: AidokuRunner.Source) {
        let key = "Browse.pinnedList"
        var pinnedList = UserDefaults.standard.stringArray(forKey: key) ?? []
        if let index = pinnedList.firstIndex(of: source.id) {
            pinnedList.remove(at: index)
            UserDefaults.standard.set(pinnedList, forKey: key)
        }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
}

// MARK: - Source List Management
extension SourceManager {

    func addSourceList(url: URL) async -> Bool {
        guard !sourceListURLs.contains(url) else {
            return false
        }

        let result = await loadSourceList(url: url)
        guard let result else {
            return false
        }

        sourceLists.append(result)
        sourceListURLs.append(url)
        for source in result.sources {
            if let sourceLanguages = source.languages {
                sourceListLanguages.formUnion(sourceLanguages)
            }
        }
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
        return true
    }

    func removeSourceList(url: URL) {
        sourceLists.removeAll { $0.url == url }
        sourceListURLs.removeAll { $0 == url }
        loadSourceListLanguages()
        UserDefaults.standard.set(sourceListsStrings, forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func clearSourceLists() {
        sourceLists = []
        sourceListURLs = []
        sourceListLanguages = []
        UserDefaults.standard.set([URL](), forKey: "Browse.sourceLists")
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func loadSourceList(url: URL) async -> SourceList? {
        let sourceList: CodableSourceList? = try? await URLSession.shared.object(from: url)
        if let sourceList {
            return sourceList.into(url: url)
        } else {
            // fall back to legacy source loading
            let externalSources: [ExternalSourceInfo]? = if !url.pathExtension.isEmpty {
                try? await URLSession.shared.object(
                    from: url
                ) as [ExternalSourceInfo]
            } else {
                if let sources = try? await URLSession.shared.object(
                    from: url.appendingPathComponent("index.min.json")
                ) as [ExternalSourceInfo] {
                    sources
                } else {
                    nil
                }
            }
            guard var externalSources else { return nil }
            for index in externalSources.indices {
                externalSources[index].sourceUrl = url
            }
            return SourceList(
                url: url,
                name: "Legacy Source List",
                sources: externalSources
            )
        }
    }

    func loadSourceListLanguages() {
        var languages = Set<String>()
        for sourceList in self.sourceLists {
            for source in sourceList.sources {
                if let sourceLanguages = source.languages {
                    languages.formUnion(sourceLanguages)
                } else if let sourceLanguage = source.lang {
                    languages.insert(sourceLanguage)
                }
            }
        }
        sourceListLanguages = languages
    }
}
