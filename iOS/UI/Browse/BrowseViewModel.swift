//
//  BrowseViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/30/22.
//

import Foundation

class BrowseViewModel {

    // TODO: source pinning
    var updatesSources: [SourceInfo2] = []
    var pinnedSources: [SourceInfo2] = []
    var installedSources: [SourceInfo2] = []
    var externalSources: [SourceInfo2] = []

    private var unfilteredExternalSources: [ExternalSourceInfo] = []

    // stored sources when searching
    private var query: String?
    private var storedUpdatesSources: [SourceInfo2]?
    private var storedPinnedSources: [SourceInfo2]?
    private var storedInstalledSources: [SourceInfo2]?
    private var storedExternalSources: [SourceInfo2]?

    // load installed sources
    func loadInstalledSources() {
        let installedSources = SourceManager.shared.sources.map { sourceToInfo(source: $0) }
        if storedInstalledSources != nil {
            storedInstalledSources = installedSources
            search(query: query)
        } else {
            self.installedSources = installedSources
        }
    }

    func loadPinnedSources() {
        let installedSources = SourceManager.shared.sources.map { sourceToInfo(source: $0) }
        let defaultPinnedSources = UserDefaults.standard.stringArray(forKey: "Browse.pinnedList") ?? []

        var pinnedSources: [SourceInfo2] = []
        for sourceId in defaultPinnedSources {
            guard let source = installedSources.first(where: { $0.sourceId == sourceId }) else {
                // remove sourceId from userdefault stored pinned list in cases such as uninstall.
                UserDefaults.standard.set(defaultPinnedSources.filter({ $0 != sourceId }), forKey: "Browse.pinnedList")
                continue
            }

            pinnedSources.append(source)
            // remove sources from the installed array.
            if let index = self.installedSources.firstIndex(of: source) {
                self.installedSources.remove(at: index)
            }
            // remove sources from the stored installed array.
            if let index = self.storedInstalledSources?.firstIndex(of: source) {
                self.storedInstalledSources?.remove(at: index)
            }
        }
        if storedPinnedSources != nil {
            storedPinnedSources = pinnedSources
            search(query: query)
        } else {
            self.pinnedSources = pinnedSources
        }
    }

    // load external source lists
    func loadExternalSources() async {
        unfilteredExternalSources = await withTaskGroup(of: [ExternalSourceInfo]?.self) { group in
            for url in SourceManager.shared.sourceLists {
                // load sources from list
                let url = url.pathExtension.isEmpty ? url : url.deletingLastPathComponent()
                group.addTask {
                    guard var sources = await SourceManager.shared.loadSourceList(url: url) else { return nil }
                    // set source url in external infos
                    for index in sources.indices {
                        sources[index].sourceUrl = url
                    }
                    return sources
                }
            }
            var ids = Set<String>() // ensure external sources have unique ids
            var results: [ExternalSourceInfo] = []
            for await result in group {
                guard let result = result else { continue }
                results += result.filter { ids.insert($0.id).inserted }
            }
            return results
        }

        filterExternalSources()
    }

    // filter external sources and updates
    // swiftlint:disable:next cyclomatic_complexity
    func filterExternalSources() {
        guard
            let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return }
        let appVersion = SemanticVersion(appVersionString)
        let selectedLanguages = UserDefaults.standard.stringArray(forKey: "Browse.languages") ?? []
        let showNsfw = UserDefaults.standard.bool(forKey: "Browse.showNsfwSources")

        var updatesSources: [SourceInfo2] = []

        var externalSources: [SourceInfo2] = unfilteredExternalSources.compactMap { info in
            var update = false
            // strip installed sources from external list
            if let installedSource = installedSources.first(where: { $0.sourceId == info.id }) {
                // check if it's an update
                if info.version > installedSource.version {
                    update = true
                } else {
                    return nil
                }
            }
            // remove pinned sources from external list
            if let pinnedSource = pinnedSources.first(where: { $0.sourceId == info.id }) {
                // check if it's an update
                if info.version > pinnedSource.version {
                    update = true
                } else {
                    return nil
                }
            }
            // check version availability
            if let minAppVersion = info.minAppVersion {
                let minAppVersion = SemanticVersion(minAppVersion)
                if minAppVersion > appVersion {
                    return nil
                }
            }
            if let maxAppVersion = info.maxAppVersion {
                let maxAppVersion = SemanticVersion(maxAppVersion)
                if maxAppVersion < appVersion {
                    return nil
                }
            }
            // add to updates after checking version
            if update {
                updatesSources.append(externalSourceToInfo(info: info))
                return nil
            }
            // hide nsfw sources
            let contentRating = SourceInfo2.ContentRating(rawValue: info.nsfw ?? 0) ?? .safe
            if !showNsfw && contentRating == .nsfw {
                return nil
            }
            // hide unselected languages
            if !selectedLanguages.contains(info.lang) {
                return nil
            }
            return externalSourceToInfo(info: info)
        }

        // sort first by name, then by language
        externalSources.sort { $0.name < $1.name }
        externalSources.sort {
            let lhs = SourceManager.languageCodes.firstIndex(of: $0.lang) ?? 0
            let rhs = SourceManager.languageCodes.firstIndex(of: $1.lang) ?? 0
            return lhs < rhs
        }

        if storedExternalSources != nil {
            storedUpdatesSources = updatesSources
            storedExternalSources = externalSources
            search(query: query)
        } else {
            self.updatesSources = updatesSources
            self.externalSources = externalSources
        }
    }

    // convert Source to SourceInfo
    private func sourceToInfo(source: Source) -> SourceInfo2 {
        SourceInfo2(
            sourceId: source.manifest.info.id,
            iconUrl: source.url.appendingPathComponent("Icon.png"),
            name: source.manifest.info.name,
            lang: source.manifest.info.lang,
            version: source.manifest.info.version,
            contentRating: SourceInfo2.ContentRating(rawValue: source.manifest.info.nsfw ?? 0) ?? .safe
        )
    }

    // convert ExternalSourceInfo to SourceInfo
    private func externalSourceToInfo(info: ExternalSourceInfo) -> SourceInfo2 {
        SourceInfo2(
            sourceId: info.id,
            iconUrl: info.sourceUrl?
                .appendingPathComponent("icons")
                .appendingPathComponent(info.icon),
            name: info.name,
            lang: info.lang,
            version: info.version,
            contentRating: SourceInfo2.ContentRating(rawValue: info.nsfw ?? 0) ?? .safe,
            externalInfo: info
        )
    }

    // filter sources by search query
    func search(query: String?) {
        self.query = query
        if let query = query?.lowercased(), !query.isEmpty {
            // store full source arrays
            if storedUpdatesSources == nil {
                storedUpdatesSources = updatesSources
                storedPinnedSources = pinnedSources
                storedInstalledSources = installedSources
                storedExternalSources = externalSources
            }
            guard
                let storedUpdatesSources = storedUpdatesSources,
                let storedPinnedSources = storedPinnedSources,
                let storedInstalledSources = storedInstalledSources,
                let storedExternalSources = storedExternalSources
            else { return }
            updatesSources = storedUpdatesSources.filter { $0.name.lowercased().contains(query) }
            pinnedSources = storedPinnedSources.filter { $0.name.lowercased().contains(query) }
            installedSources = storedInstalledSources.filter { $0.name.lowercased().contains(query) }
            externalSources = storedExternalSources.filter { $0.name.lowercased().contains(query) }
        } else {
            // reset search, restore source arrays
            if let storedUpdatesSources = storedUpdatesSources {
                updatesSources = storedUpdatesSources
                self.storedUpdatesSources = nil
            }
            if let storedPinnedSources = storedPinnedSources {
                pinnedSources = storedPinnedSources
                self.storedPinnedSources = nil
            }
            if let storedInstalledSources = storedInstalledSources {
                installedSources = storedInstalledSources
                self.storedInstalledSources = nil
            }
            if let storedExternalSources = storedExternalSources {
                externalSources = storedExternalSources
                self.storedExternalSources = nil
            }
        }
    }
}
