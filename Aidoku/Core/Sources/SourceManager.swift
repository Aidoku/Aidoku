//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import AidokuRunner
import Foundation
import UIKit
import ZIPFoundation

actor SourceManager {
    static let shared = SourceManager()

    static let directory = FileManager.default.applicationSupportDirectory.appendingPathComponent("Sources", isDirectory: true)
    static let oldDirectory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true) // used for migration

    @MainActor var store: SourceStore { SourceStore.shared }

    private var sourcesByKey: [String: AidokuRunner.Source] = [:]
    private var disabledSourceKeys: Set<String> = []
    private var sourceLanguageCodes: Set<String> = []

    private var sourceListURLs: Set<URL>
    private var sourceListLanguageCodes: Set<String> = []

    private var loadSourcesTask: Task<(), Never>?
    private var loadSourceListsTask: Task<(), Never>?

    private enum SourceListLoadState {
        case loading
        case loaded(SourceList)
        case unavailable
    }

    private struct SourceListStreamSubscriber {
        let generation: Int
        let continuation: AsyncStream<URL>.Continuation
    }

    private var sourceListStates: [URL: SourceListLoadState] = [:]
    private var sourceListStreamSubscribers: [UUID: SourceListStreamSubscriber] = [:]
    private var sourceListLoadGeneration = 0

    var sourceListLoadFinished = false

    private init() {
        sourceListURLs = AppSettings.browse.sourceLists.get()
        disabledSourceKeys = AppSettings.browse.disabledSources.get()
    }

    // queue the loading of sources and source lists
    func start() {
        loadSourcesTask = Task {
            await reloadSources()
        }
        startSourceListsReload()
    }
}

// MARK: Source Loading
extension SourceManager {
    func waitForSourcesLoad() async {
        await loadSourcesTask?.value
    }

    func reloadSources() async {
        sourcesByKey = await getInstalledSources()
        loadSourceLanguages()

        await publishSourceState()
        notifySourcesLoaded(keys: sourcesByKey.keys)

        await loadLegacySourceFilters()
    }

    private func getInstalledSources() async -> [String: AidokuRunner.Source] {
        let objects: [SourceObjectData] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSources(context: context).map { $0.toData() }
        }
        var sourcesByKey: [String: AidokuRunner.Source] = [:]
        for dbSource in objects where !disabledSourceKeys.contains(dbSource.id) {
            if let source = await dbSource.toNewSource() {
                if sourcesByKey[source.key] != nil {
                    // remove duplicate coredata sources
                    CoreDataManager.shared.remove(dbSource.objectID)
                } else {
                    sourcesByKey[source.key] = source
                }
            } else {
                LogManager.logger.error("Failed to load source \(dbSource.id)")
            }
        }
        return sourcesByKey
    }

    private func loadLegacySourceFilters() async {
        await withTaskGroup(of: Void.self) { group in
            for source in sourcesByKey.values {
                if let legacySource = source.legacySource {
                    group.addTask {
                        _ = try? await legacySource.getFilters()
                    }
                }
            }
        }
        NotificationCenter.default.post(name: .loadedSourceFilters, object: nil)
    }
}

// MARK: Source List Loading
extension SourceManager {
    func waitForSourceListsLoad() async {
        await loadSourceListsTask?.value
    }

    func startSourceListsReload(skipUpdateNotification: Bool = false) {
        if let loadSourcesTask {
            loadSourcesTask.cancel()
            finishSourceListStreams()
        }

        sourceListLoadGeneration += 1
        sourceListLoadFinished = false

        let generation = sourceListLoadGeneration
        let urls = sourceListURLs

        sourceListStates = Dictionary(uniqueKeysWithValues: urls.map { ($0, .loading) })

        loadSourceListsTask = Task { [weak self] in
            await self?.loadSourceLists(
                urls: urls,
                generation: generation,
                skipUpdateNotification: skipUpdateNotification
            )
        }
    }

    func streamSourceListsLoad() -> AsyncStream<URL> {
        let (stream, continuation) = AsyncStream<URL>.makeStream()
        let id = UUID()
        let generation = sourceListLoadGeneration

        for url in sourceListURLs {
            guard let state = sourceListStates[url] else { continue }
            if case .loading = state { continue }
            continuation.yield(url)
        }

        if sourceListLoadFinished {
            continuation.finish()
            return stream
        }

        sourceListStreamSubscribers[id] = .init(generation: generation, continuation: continuation)

        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSourceListStreamSubscriber(id)
            }
        }

        return stream
    }

    func getSourceList(url: URL) -> SourceList? {
        guard case let .loaded(sourceList) = sourceListStates[url] else {
            return nil
        }
        return sourceList
    }

    private func removeSourceListStreamSubscriber(_ id: UUID) {
        sourceListStreamSubscribers[id] = nil
    }

    private func loadSourceLists(
        urls: Set<URL>,
        generation: Int,
        skipUpdateNotification: Bool
    ) async {
        await withTaskGroup(of: (URL, SourceList?).self) { group in
            for url in urls {
                group.addTask {
                    let sourceList = await self.loadSourceList(url: url)
                    return (url, sourceList)
                }
            }

            for await (url, sourceList) in group {
                guard generation == sourceListLoadGeneration else { return }

                if let sourceList {
                    sourceListStates[url] = .loaded(sourceList)
                } else {
                    sourceListStates[url] = .unavailable
                }
                for subscriber in sourceListStreamSubscribers.values where subscriber.generation == generation {
                    subscriber.continuation.yield(url)
                }
            }
        }

        guard generation == sourceListLoadGeneration else { return }

        await loadSourceListLanguages()

        sourceListLoadFinished = true
        loadSourceListsTask = nil

        finishSourceListStreams(generation: generation)

        if !skipUpdateNotification {
            notifySourceListsLoaded()
        }
    }

    private func finishSourceListStreams(generation: Int? = nil) {
        let ids = sourceListStreamSubscribers.compactMap { id, subscriber -> UUID? in
            guard generation == nil || subscriber.generation == generation else {
                return nil
            }
            subscriber.continuation.finish()
            return id
        }

        for id in ids {
            sourceListStreamSubscribers.removeValue(forKey: id)
        }
    }

    private func loadSourceList(url: URL) async -> SourceList? {
        let session = URLSession.withTimeoutInterval(15)
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let sourceList = try? JSONDecoder().decode(CodableSourceList.self, from: data)

        if let sourceList {
            return sourceList.into(url: url)
        } else {
            return await loadLegacySourceList(url: url, session: session, data: data)
        }
    }

    private func loadLegacySourceList(url: URL, session: URLSession, data: Data) async -> SourceList? {
        let externalSources: [ExternalSourceInfo]? = if !url.pathExtension.isEmpty {
            try? JSONDecoder().decode([ExternalSourceInfo].self, from: data)
        } else {
            if let sources = try? await session.object(
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
            name: NSLocalizedString("LEGACY_SOURCE_LIST"),
            sources: externalSources,
            legacy: true
        )
    }
}

// MARK: Source Info Fetching
extension SourceManager {
    func getSourceInfos(sorted: Bool = true, includeDisabled: Bool = true) async -> [SourceInfo] {
        await waitForSourcesLoad()

        var sourceById: [String: ExternalSourceInfo] = [:]
        for state in sourceListStates.values {
            guard case let .loaded(sourceList) = state else { continue }
            for source in sourceList.sources {
                if let existing = sourceById[source.id] {
                    // if a newer version exists, replace it
                    if source.version > existing.version {
                        sourceById[source.id] = source
                    }
                } else {
                    sourceById[source.id] = source
                }
            }
        }

        let objects: [SourceObjectData] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getSources(context: context).map { $0.toData() }
        }
        var infos: [SourceInfo] = objects
            .compactMap { source in
                guard var info = source.toInfo() else { return nil }
                let disabled = disabledSourceKeys.contains(info.sourceId)
                if !includeDisabled {
                    return nil
                }
                info.disabled = disabled
                info.externalInfo = sourceById[info.sourceId]
                return info
            }
        if sorted {
            infos.sort { lhs, rhs in
                let languageOrder = SourceLanguage.compare(lhs.languages, rhs.languages)
                if languageOrder != .orderedSame {
                    return languageOrder == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        return infos
    }

    func getLoadedSources() async -> [AidokuRunner.Source] {
        await waitForSourcesLoad()
        return Array(sourcesByKey.values)
    }

    func getSourceLists() async -> [SourceList] {
        await waitForSourceListsLoad()
        return sourceListStates.values
            .compactMap {
                guard case let .loaded(sourceList) = $0 else { return nil }
                return sourceList
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func getSourceListURLs() -> Set<URL> {
        sourceListURLs
    }

    func getLoadedSourceLists() async -> [URL: SourceList] {
        sourceListStates.reduce(into: [URL: SourceList]()) { result, item in
            guard case let .loaded(sourceList) = item.value else {
                return
            }
            result[item.key] = sourceList
        }
    }

    func getMissingSourceLists() async -> Set<URL> {
        sourceListURLs.filter {
            if case .unavailable = sourceListStates[$0] {
                true
            } else {
                false
            }
        }
    }

    func getSourceLanguages() -> Set<String> {
        sourceLanguageCodes
    }

    func getSourceListLanguages() -> Set<String> {
        sourceListLanguageCodes
    }

    func source(for key: String) async -> AidokuRunner.Source? {
        await waitForSourcesLoad()
        return sourcesByKey[key]
    }
}

// MARK: - Source Management
extension SourceManager {
    func missingExternalSourceKeys(in keys: Set<String>) async -> Set<String> {
        let installedKeys: Set<String> = await CoreDataManager.shared.container.performBackgroundTask { context in
            Set(CoreDataManager.shared.getSources(context: context).compactMap(\.id))
        }
        return keys.subtracting(installedKeys)
    }

    /// Installs missing sources with matching entries in the currently loaded source lists.
    ///
    /// If multiple lists contain the same source, the newest compatible version is used.
    func installExternalSources(
        keys: Set<String>,
        progressReport: @MainActor @Sendable (_ name: String, _ key: String, _ current: Int, _ total: Int) -> Void
    ) async -> Set<String> {
        guard
            !keys.isEmpty,
            let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else {
            return []
        }

        let missingKeys = await missingExternalSourceKeys(in: keys)
        guard !missingKeys.isEmpty else { return [] }

        let appVersion = SemanticVersion(appVersionString)
        var sourcesByKey: [String: ExternalSourceInfo] = [:]

        for state in sourceListStates.values {
            guard case let .loaded(sourceList) = state else { continue }
            for source in sourceList.sources where missingKeys.contains(source.id) && source.fileURL != nil {
                if
                    let minAppVersion = source.minAppVersion.flatMap(SemanticVersion.init),
                    minAppVersion > appVersion
                {
                    continue
                }
                if
                    let maxAppVersion = source.maxAppVersion.flatMap(SemanticVersion.init),
                    maxAppVersion < appVersion
                {
                    continue
                }

                if let existing = sourcesByKey[source.id] {
                    if source.version > existing.version {
                        sourcesByKey[source.id] = source
                    }
                } else {
                    sourcesByKey[source.id] = source
                }
            }
        }

        let sources = missingKeys.sorted().compactMap { sourcesByKey[$0] }
        var installedKeys: Set<String> = []
        for (index, source) in sources.enumerated() {
            guard let url = source.fileURL else { continue }
            await progressReport(source.name, source.id, index + 1, sources.count)
            if let installedSource = await importSource(from: url) {
                installedKeys.insert(installedSource.key)
            }
        }
        return installedKeys
    }

    func importSource(from url: URL) async -> AidokuRunner.Source? {
        // download and unzip source aix
        guard let temporaryDirectory = FileManager.default.createTemporaryDirectory() else { return nil }
        var secured = false
        var fileUrl = url
        if !fileUrl.isFileURL {
            do {
                let (location, _) = try await URLSession.shared.download(for: URLRequest.from(url))
                fileUrl = location
            } catch {
                LogManager.logger.error("Failed to download source from \(url.absoluteString): \(error)")
                return nil
            }
        } else {
            secured = url.startAccessingSecurityScopedResource()
        }
        defer {
            if secured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
        } catch {
            LogManager.logger.error("Failed to unarchive source package: \(error)")
            return nil
        }

        // try initializing the source
        let payload = temporaryDirectory.appendingPathComponent("Payload")
        var newSource: AidokuRunner.Source?
        let legacySource: Source?

        do {
            newSource = try await AidokuRunner.Source(url: payload)
            legacySource = nil
        } catch {
            newSource = nil
            legacySource = try? Source(from: payload)

            if legacySource == nil {
                LogManager.logger.error("Failed to load source: \(error)")
                return nil
            }
        }

        // ensure source key is valid
        let sourceKey: String
        if let newSource {
            sourceKey = newSource.key
        } else if let legacySource {
            sourceKey = legacySource.id
        } else {
            return nil
        }
        guard isValidSourceKey(sourceKey) else {
            LogManager.logger.error("Invalid source key: \(sourceKey)")
            return nil
        }

        // move to final location
        Self.directory.createDirectory()
        let destination = Self.directory.appendingPathComponent(sourceKey)
        if destination.exists {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.moveItem(at: payload, to: destination)
        } catch {
            LogManager.logger.error("Failed to unarchive source package: \(error)")
            return nil
        }
        try? FileManager.default.removeItem(at: temporaryDirectory)

        // update initialized location
        let result: AidokuRunner.Source
        if newSource != nil {
            do {
                result = try await AidokuRunner.Source(key: sourceKey, url: destination)
            } catch {
                LogManager.logger.error("Failed to load moved source: \(error)")
                return nil
            }
        } else if let legacySource {
            legacySource.url = destination
            result = .legacy(source: legacySource)
        } else {
            return nil
        }

        // remove old source version (on update) and add new version to coredata
        let installedSource = sourcesByKey.removeValue(forKey: sourceKey)

        await CoreDataManager.shared.container.performBackgroundTask { [result] context in
            CoreDataManager.shared.removeSource(key: sourceKey, context: context)
            CoreDataManager.shared.createSource(source: result, context: context)
            try? context.save()
        }

        // if there was a breaking change, prompt for migration
        if
            let installedVersion = installedSource?.version,
            let breakingChangeVersion = result.config?.breakingChangeVersion,
            installedVersion < breakingChangeVersion
        {
            Task { @MainActor in
                UIApplication.shared.appDelegate?.handleSourceMigration(source: result)
            }
        }

        if let legacySource {
            Task {
                _ = try? await legacySource.getFilters()
            }
        }

        sourcesByKey[result.key] = result
        sourceLanguageCodes.formUnion(result.languages)

        await publishSourceState()
        notifySourcesLoaded(keys: [result.key])

        return result
    }

    enum CustomSourceKind {
        case local
        case komga(ServerConfig)
        case kavita(ServerConfig)
        case suwayomi(ServerConfig)

        struct ServerConfig {
            let name: String
            let server: URL
            var username: String?
            var password: String?
        }
    }

    @discardableResult
    func createCustomSource(_ kind: CustomSourceKind) async -> String? {
        let config: CustomSourceConfig
        switch kind {
            case .local:
                config = CustomSourceConfig.local
            case .komga(let serverConfig), .kavita(let serverConfig), .suwayomi(let serverConfig):
                let name = serverConfig.name
                let server = serverConfig.server
                let username = serverConfig.username
                let password = serverConfig.password

                let keyPrefix = switch kind {
                    case .komga: KomgaSourceRunner.sourceKeyPrefix
                    case .kavita: KavitaSourceRunner.sourceKeyPrefix
                    case .suwayomi: SuwayomiSourceRunner.sourceKeyPrefix
                    case .local: unreachable()
                }
                let nameEncoded = name.lowercased().replacingOccurrences(of: " ", with: "-")
                var key = "\(keyPrefix).\(nameEncoded)"

                // make sure key is unique
                var counter = 1
                while sourcesByKey[key] != nil || disabledSourceKeys.contains(key) {
                    key = "\(keyPrefix).\(nameEncoded)-\(counter)"
                    counter += 1
                }

                let configValues = CustomSourceConfig.KeyNameServer(key: key, name: name, server: server.absoluteString)
                config = switch kind {
                    case .komga: CustomSourceConfig.komga(configValues)
                    case .kavita: CustomSourceConfig.kavita(configValues)
                    case .suwayomi: CustomSourceConfig.suwayomi(configValues)
                    case .local: unreachable()
                }

                // register details
                var url = server.absoluteString
                if url.last == "/" {
                    url.removeLast()
                }
                UserDefaults.standard.setValue(url, forKey: "\(key).server")
                if username != nil || password != nil {
                    UserDefaults.standard.setValue("logged_in", forKey: "\(key).login")
                }
                if let username {
                    UserDefaults.standard.setValue(username, forKey: "\(key).login.username")
                }
                if let password {
                    UserDefaults.standard.setValue(password, forKey: "\(key).login.password")
                }
        }
        let source = config.toSource()

        // add to coredata
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let result = CoreDataManager.shared.createSource(source: source, context: context)
            result.customSource = config.encode() as NSObject
            try? context.save()
        }

        sourcesByKey[source.key] = source

        await publishSourceState()
        notifySourcesLoaded(keys: [source.key])

        return source.key
    }

    func updateCustomSource(key: String, config: CustomSourceConfig, updateSourceList: Bool = false) async {
        let newDbSource = await CoreDataManager.shared.container.performBackgroundTask { context in
            let source = CoreDataManager.shared.getSource(key: key, context: context)
            source?.customSource = config.encode() as NSObject
            try? context.save()
            return source?.toData()
        }
        if updateSourceList, let newSource = await newDbSource?.toNewSource() {
            sourcesByKey[newSource.key] = newSource
            await publishSourceState()
            notifySourcesLoaded(keys: [newSource.key])
        }
    }

    func clearSources() async {
        let objects: [SourceObjectData] = await CoreDataManager.shared.container.performBackgroundTask { context in
            let objects = CoreDataManager.shared.getSources(context: context).map { $0.toData() }

            CoreDataManager.shared.clearSources(context: context)
            try? context.save()

            return objects
        }

        var sourceKeys: [String] = []
        sourceKeys.reserveCapacity(objects.count)

        for object in objects {
            sourceKeys.append(object.id)

            removeSettings(from: object.id)
            await removeEnhancedTrackerItems(for: object.id)

            // remove from filesystem
            if let path = object.path {
                let url = FileManager.default.applicationSupportDirectory.appendingPathComponent(path)
                url.removeItem()
            }
        }

        // remove pinned and disabled sources
        AppSettings.browse.pinnedList.reset()
        AppSettings.browse.disabledSources.reset()

        sourcesByKey = [:]

        await publishSourceState()
        notifySourcesUnloaded(keys: sourceKeys)
    }

    func remove(sourceKey: String, skipUpdateNotification: Bool = false) async {
        let data: SourceObjectData? = await CoreDataManager.shared.container.performBackgroundTask { context in
            let data = CoreDataManager.shared.getSource(key: sourceKey, context: context)?.toData()
            if data != nil {
                CoreDataManager.shared.removeSource(key: sourceKey, context: context)
                try? context.save()
            }
            return data
        }
        guard let data else { return }

        if let path = data.path {
            let url = FileManager.default.applicationSupportDirectory.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
        }

        sourcesByKey.removeValue(forKey: sourceKey)
        removeSettings(from: sourceKey)
        unpin(sourceKey: sourceKey, skipUpdateNotification: true)
        await enable(sourceKey: sourceKey, skipUpdateNotification: true)
        await removeEnhancedTrackerItems(for: sourceKey)

        if !skipUpdateNotification {
            await publishSourceState()
            notifySourcesUnloaded(keys: [sourceKey])
        }
    }

    nonisolated func removeSettings(from sourceKey: String) {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys

        for key in keys where key.hasPrefix(sourceKey) {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func removeEnhancedTrackerItems(for sourceKey: String) async {
        if sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
            await TrackerManager.komga.removeTrackItems(sourceKey: sourceKey)
        } else if sourceKey.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
            await TrackerManager.kavita.removeTrackItems(sourceKey: sourceKey)
        } else if sourceKey.hasPrefix(SuwayomiSourceRunner.sourceKeyPrefix) {
            await TrackerManager.suwayomi.removeTrackItems(sourceKey: sourceKey)
        }
    }
}

// MARK: Pinned Sources
extension SourceManager {
    /// Gets a list of pinned sources.
    func getPinned() -> [AidokuRunner.Source] {
        AppSettings.browse.pinnedList.get()
            .compactMap { sourcesByKey[$0] }
    }

    // Pin a source in browse tab.
    nonisolated func pin(sourceKey: String) {
        var pinnedList = AppSettings.browse.pinnedList.get()
        if !pinnedList.contains(sourceKey) {
            pinnedList.append(sourceKey)
            AppSettings.browse.pinnedList.set(pinnedList)
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
    }

    // Unpin a source in browse tab.
    nonisolated func unpin(sourceKey: String, skipUpdateNotification: Bool = false) {
        var pinnedList = AppSettings.browse.pinnedList.get()
        if let index = pinnedList.firstIndex(of: sourceKey) {
            pinnedList.remove(at: index)
            AppSettings.browse.pinnedList.set(pinnedList)
            if !skipUpdateNotification {
                NotificationCenter.default.post(name: .updateSourceList, object: nil)
            }
        }
    }
}

// MARK: Disabled Sources
extension SourceManager {
    func disable(sourceKey: String) async {
        let (inserted, _) = disabledSourceKeys.insert(sourceKey)
        if inserted {
            AppSettings.browse.disabledSources.set(disabledSourceKeys)
            sourcesByKey.removeValue(forKey: sourceKey)
            await publishSourceState()
            notifySourcesUnloaded(keys: [sourceKey])
        }
    }

    func enable(sourceKey: String, skipUpdateNotification: Bool = false) async {
        let removed = disabledSourceKeys.remove(sourceKey) != nil
        if removed {
            AppSettings.browse.disabledSources.set(disabledSourceKeys)
            let object: SourceObjectData? = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getSource(key: sourceKey, context: context)?.toData()
            }
            guard let object, let source = await object.toNewSource() else {
                LogManager.logger.error("Failed to load source \(sourceKey)")
                return
            }
            sourcesByKey[source.key] = source
            await publishSourceState()
            notifySourcesLoaded(keys: [source.key], skipUpdateNotification: skipUpdateNotification)
        }
    }

    // checks if a source key matches ^[A-Za-z0-9.\-]+$ and doesn't use a reserved prefix
    private nonisolated func isValidSourceKey(_ sourceKey: String) -> Bool {
        guard !sourceKey.isEmpty else {
            return false
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let allCharactersValid = sourceKey.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
        guard allCharactersValid else {
            return false
        }

        let reservedPrefixes = [
            "local",
            KomgaSourceRunner.sourceKeyPrefix,
            KavitaSourceRunner.sourceKeyPrefix,
            SuwayomiSourceRunner.sourceKeyPrefix
        ] // built-in sources
            + BackupManager.allowedSettingsPrefixes
            + BackupManager.excludedSettingsPrefixes
        let usesReservedPrefix = reservedPrefixes.contains(where: { sourceKey.hasPrefix($0) })
        guard !usesReservedPrefix else {
            return false
        }

        return true
    }
}

// MARK: - Source List Management
extension SourceManager {
    func addSourceList(url: URL, allowUnavailable: Bool = false) async -> Bool {
        guard !sourceListURLs.contains(url) else {
            return false
        }

        let result = await loadSourceList(url: url)
        if !allowUnavailable && result == nil {
            return false
        }

        sourceListURLs.insert(url)
        AppSettings.browse.sourceLists.set(sourceListURLs)

        if let result {
            sourceListStates[url] = .loaded(result)
            for source in result.sources {
                if let sourceLanguages = source.languages {
                    sourceListLanguageCodes.formUnion(sourceLanguages)
                } else if let sourceLang = source.lang {
                    sourceListLanguageCodes.insert(sourceLang)
                }
            }
        } else {
            sourceListStates[url] = .unavailable
        }

        NotificationCenter.default.post(name: .updateSourceLists, object: nil)

        return true
    }

    func removeSourceList(url: URL) async {
        sourceListStates.removeValue(forKey: url)
        sourceListURLs.remove(url)
        AppSettings.browse.sourceLists.set(sourceListURLs)
        await loadSourceListLanguages()
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }

    func clearSourceLists() async {
        sourceListStates = [:]
        sourceListURLs = []
        sourceListLanguageCodes = []
        AppSettings.browse.sourceLists.reset()
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }
}

// MARK: Language Loading
extension SourceManager {
    private func loadSourceListLanguages() async {
        var languages = Set<String>()
        for state in sourceListStates.values {
            guard case let .loaded(sourceList) = state else { continue }
            for source in sourceList.sources {
                if let sourceLanguages = source.languages {
                    languages.formUnion(sourceLanguages)
                } else if let sourceLanguage = source.lang {
                    languages.insert(sourceLanguage)
                }
            }
        }
        sourceListLanguageCodes = languages
    }

    private func loadSourceLanguages() {
        var languages = Set<String>()
        for source in sourcesByKey.values {
            languages.formUnion(source.languages)
        }
        sourceLanguageCodes = languages
    }
}

// MARK: Notifications
extension SourceManager {
    private func publishSourceState() async {
        await MainActor.run { [sourcesByKey, disabledSourceKeys] in
            store.update(
                sourcesByKey: sourcesByKey,
                disabledSourceKeys: disabledSourceKeys
            )
        }
    }

    private func notifySourcesLoaded(keys: some Sequence<String>, skipUpdateNotification: Bool = false) {
        for sourceKey in keys {
            NotificationCenter.default.post(name: .sourceLoaded, object: sourceKey)
        }
        if !skipUpdateNotification {
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
    }

    private func notifySourcesUnloaded(keys: some Sequence<String>, skipUpdateNotification: Bool = false) {
        for sourceKey in keys {
            NotificationCenter.default.post(name: .sourceUnloaded, object: sourceKey)
        }
        if !skipUpdateNotification {
            NotificationCenter.default.post(name: .updateSourceList, object: nil)
        }
    }

    private func notifySourceListsLoaded() {
        NotificationCenter.default.post(name: .updateSourceLists, object: nil)
    }
}
