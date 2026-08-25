//
//  BrowseViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/30/22.
//

import Foundation
import AidokuRunner

@MainActor
class BrowseViewModel {
    var updatesSources: [SourceInfo] = []
    var pinnedSources: [SourceInfo] = []
    var installedSources: [SourceInfo] = []

    var unfilteredExternalSources: [ExternalSourceInfo] = []

    var hasLegacySourceList = false

    // stored sources when searching
    private var query: String?
    private var storedUpdatesSources: [SourceInfo]?
    private var storedPinnedSources: [SourceInfo]?
    private var storedInstalledSources: [SourceInfo]?

    func loadInstalledSources() async {
        let installedSources = await SourceManager.shared.getSourceInfos()
        if storedInstalledSources != nil {
            storedInstalledSources = installedSources
            search(query: query)
        } else {
            self.installedSources = installedSources
        }
    }

    func loadPinnedSources() async {
        let installedSources = storedInstalledSources ?? installedSources
        var defaultPinnedSources = AppSettings.browse.pinnedList.get()

        var pinnedSources: [SourceInfo] = []
        for sourceId in defaultPinnedSources {
            guard let source = installedSources.first(where: { $0.sourceId == sourceId }) else {
                // remove sourceId from userdefault stored pinned list in cases such as uninstall.
                defaultPinnedSources = defaultPinnedSources.filter({ $0 != sourceId })
                AppSettings.browse.pinnedList.set(defaultPinnedSources)
                continue
            }

            pinnedSources.append(source)
            // remove source from the installed array.
            if let index = self.installedSources.firstIndex(where: { $0.sourceId == sourceId }) {
                self.installedSources.remove(at: index)
            }
            // remove source from the stored installed array.
            if let index = self.storedInstalledSources?.firstIndex(where: { $0.sourceId == sourceId }) {
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
    func loadExternalSources(reload: Bool = false) async {
        if reload {
            await SourceManager.shared.reloadSourceLists(skipUpdateNotification: true)
        }
        let sourceLists = await SourceManager.shared.getSourceLists()

        // ensure external sources have unique ids
        var sourceById: [String: ExternalSourceInfo] = [:]

        for sourceList in sourceLists {
            if sourceList.legacy {
                hasLegacySourceList = true
            }
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

        unfilteredExternalSources = Array(sourceById.values)

        func updateExternalInfo(for property: inout [SourceInfo]) {
            property = property.map { info in
                if let externalInfo = sourceById[info.sourceId] {
                    var updatedInfo = info
                    updatedInfo.externalInfo = externalInfo
                    return updatedInfo
                }
                return info
            }
        }

        if query?.isEmpty ?? true {
            updateExternalInfo(for: &pinnedSources)
            updateExternalInfo(for: &installedSources)
        }
    }

    func loadUpdates() {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let appVersion = SemanticVersion(appVersionString)

        updatesSources = unfilteredExternalSources
            .compactMap { info -> SourceInfo? in
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

                if let installedSource = installedSources.first(where: { $0.sourceId == info.id }) {
                    if info.version > installedSource.version {
                        return info.toInfo()
                    }
                    return nil
                }
                if let pinnedSource = pinnedSources.first(where: { $0.sourceId == info.id }) {
                    if info.version > pinnedSource.version {
                        return info.toInfo()
                    }
                    return nil
                }
                return nil
            }
            .sorted { lhs, rhs in
                let languageOrder = SourceLanguage.compare(lhs.languages, rhs.languages)
                if languageOrder != .orderedSame {
                    return languageOrder == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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
            }
            guard
                let storedUpdatesSources = storedUpdatesSources,
                let storedPinnedSources = storedPinnedSources,
                let storedInstalledSources = storedInstalledSources
            else { return }
            updatesSources = storedUpdatesSources.filter { $0.name.lowercased().contains(query) }
            pinnedSources = storedPinnedSources.filter { $0.name.lowercased().contains(query) }
            installedSources = storedInstalledSources.filter { $0.name.lowercased().contains(query) }
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
        }
    }
}
