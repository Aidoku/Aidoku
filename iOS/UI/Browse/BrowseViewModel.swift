//
//  BrowseViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/30/22.
//

import Foundation
import AidokuRunner

class BrowseViewModel {

    var updatesSources: [SourceInfo2] = []
    var pinnedSources: [SourceInfo2] = []
    var installedSources: [SourceInfo2] = []

    var unfilteredExternalSources: [ExternalSourceInfo] = []

    // stored sources when searching
    private var query: String?
    private var storedUpdatesSources: [SourceInfo2]?
    private var storedPinnedSources: [SourceInfo2]?
    private var storedInstalledSources: [SourceInfo2]?
    private var storedExternalSources: [SourceInfo2]?

    private func getInstalledSources() -> [SourceInfo2] {
        SourceManager.shared.sources.map { $0.toInfo() }
    }

    // load installed sources
    func loadInstalledSources() {
        let installedSources = getInstalledSources()
        if storedInstalledSources != nil {
            storedInstalledSources = installedSources
            search(query: query)
        } else {
            self.installedSources = installedSources
        }
    }

    func loadPinnedSources() {
        let installedSources = getInstalledSources()
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
    func loadExternalSources(reload: Bool = false) async {
        await SourceManager.shared.loadSourceLists(reload: reload)

        // ensure external sources have unique ids
        var sourceById: [String: ExternalSourceInfo] = [:]

        for sourceList in SourceManager.shared.sourceLists {
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
    }

    func loadUpdates() {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let appVersion = SemanticVersion(appVersionString)

        updatesSources = unfilteredExternalSources.compactMap { info -> SourceInfo2? in
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
