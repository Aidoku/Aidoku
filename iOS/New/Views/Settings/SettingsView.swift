//
//  SettingsView.swift
//  Aidoku
//
//  Created by Skitty on 9/17/25.
//

import AidokuRunner
import Nuke
import SwiftUI
import WebKit

struct SettingsView: View {
    @State private var categories: [String]

    @State private var searchText: String = ""
    @State private var searchResult: SettingSearchResult?

    @EnvironmentObject private var path: NavigationCoordinator

    static let settings = Settings.settings

    init() {
        self._categories = State(initialValue: CoreDataManager.shared.getCategoryTitles())
    }
}

extension SettingsView {
    var body: some View {
        List {
            if searchText.isEmpty {
                ForEach(Self.settings.indices, id: \.self) { offset in
                    let setting = Self.settings[offset]
                    SettingView(setting: setting, onChange: onSettingChange)
                        .settingPageContent(pageContentHandler)
                        .settingCustomContent(customContentHandler)
                }
            } else if let searchResult {
                Group {
                    ForEach(searchResult.sections, id: \.id) { section in
                        Section {
                            ForEach(section.paths.indices, id: \.self) { offset in
                                let setting = section.paths[offset]
                                if setting.paths.count == 1, let setting = setting.setting {
                                    // if it's root level, just show itself
                                    SettingView(setting: setting, onChange: onSettingChange)
                                        .settingPageContent(pageContentHandler)
                                        .settingCustomContent(customContentHandler)
                                } else {
                                    Button {
                                        openSearchPage(for: setting)
                                    } label: {
                                        NavigationLink(destination: EmptyView()) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(setting.title.highlight(text: searchText))

                                                HStack(spacing: 2) {
                                                    ForEach(Array(zip(setting.paths.indices, setting.paths)), id: \.0.self) { index, title in
                                                        Text(title)
                                                        if index < setting.paths.count - 1 {
                                                            Image(systemName: "arrow.forward")
                                                        }
                                                    }
                                                }
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        } header: {
                            if section.icon != nil || section.header != nil {
                                HStack {
                                    if let icon = section.icon {
                                        Group {
                                            let iconSize: CGFloat = 29
                                            switch icon {
                                                case .system(let name, let color, let inset):
                                                    Image(systemName: name)
                                                        .resizable()
                                                        .renderingMode(.template)
                                                        .foregroundStyle(.white)
                                                        .aspectRatio(contentMode: .fit)
                                                        .padding(CGFloat(inset))
                                                        .frame(width: iconSize, height: iconSize)
                                                        .background(color.toColor())
                                                        .clipShape(RoundedRectangle(cornerRadius: 6.5))
                                                case .url(let string):
                                                    SourceImageView(
                                                        imageUrl: string,
                                                        width: iconSize,
                                                        height: iconSize,
                                                        downsampleWidth: iconSize * 2
                                                    )
                                                    .clipShape(RoundedRectangle(cornerRadius: 6.5))
                                            }
                                        }
                                        .scaleEffect(0.75)
                                    }
                                    if let header = section.header {
                                        Text(header)
                                    }
                                    Spacer()
                                }
                            }

                        }
                    }
                }
            }
        }
        .overlay {
            if let searchResult, searchResult.sections.isEmpty {
                UnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText)
        .navigationTitle(NSLocalizedString("SETTINGS"))
        .onChange(of: searchText) { _ in
            search()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateCategories)) { _ in
            categories = CoreDataManager.shared.getCategoryTitles()
            if
                let selected = UserDefaults.standard.string(forKey: "Library.defaultCategory"),
                !selected.isEmpty && selected != "none" && !categories.contains(selected)
            {
                UserDefaults.standard.removeObject(forKey: "Library.defaultCategory")
            }
        }
    }
}

extension SettingsView {
    func onSettingChange(_ key: String) {
        switch key {
            case "General.appearance", "General.useSystemAppearance":
                if !UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                    if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                        UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .light
                    } else {
                        UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .dark
                    }
                } else {
                    UIApplication.shared.firstKeyWindow?.overrideUserInterfaceStyle = .unspecified
                }

            case "Logs.logServer":
                LogManager.logger.streamUrl = UserDefaults.standard.string(forKey: "Logs.logServer").flatMap(URL.init)
            case "Logs.export":
                let url = LogManager.export()
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                guard let sourceView = path.rootViewController?.view else { return }
                vc.popoverPresentationController?.sourceView = sourceView
                path.present(vc)
            case "Logs.display":
                path.push(LogViewController())

            case "Advanced.clearTrackedManga":
                confirmAction(
                    title: NSLocalizedString("CLEAR_TRACKED_MANGA"),
                    message: NSLocalizedString("CLEAR_TRACKED_MANGA_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                    }
                }
            case "Advanced.clearNetworkCache":
                var totalCacheSize = URLCache.shared.currentDiskUsage
                if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
                    totalCacheSize += nukeCache.totalSize
                }
                let message = NSLocalizedString("CLEAR_NETWORK_CACHE_TEXT")
                    + "\n\n"
                    + String(
                        format: NSLocalizedString("CACHE_SIZE_%@"),
                        ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file)
                    )

                confirmAction(
                    title: NSLocalizedString("CLEAR_NETWORK_CACHE"),
                    message: message
                ) {
                    self.clearNetworkCache()
                }
            case "Advanced.clearReadHistory":
                confirmAction(
                    title: NSLocalizedString("CLEAR_READ_HISTORY"),
                    message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearHistory(context: context)
                            try? context.save()
                        }
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                    }
                }
            case "Advanced.clearExcludingLibrary":
                confirmAction(
                    title: NSLocalizedString("CLEAR_EXCLUDING_LIBRARY"),
                    message: NSLocalizedString("CLEAR_EXCLUDING_LIBRARY_TEXT")
                ) {
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearHistoryExcludingLibrary(context: context)
                            try? context.save()
                        }
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                    }
                }
            case "Advanced.migrateHistory":
                confirmAction(
                    title: "Migrate Chapter History",
                    // swiftlint:disable:next line_length
                    message: "This will migrate leftover reading history from old versions that are not currently linked with stored chapters in the local database. This should've happened automatically upon updating, but if it didn't complete, it can be re-executed this way."
                ) {
                    Task {
                        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator(style: .progress)
                        await CoreDataManager.shared.migrateChapterHistory(progress: { progress in
                            Task { @MainActor in
                                (UIApplication.shared.delegate as? AppDelegate)?.indicatorProgress = progress
                            }
                        })
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                }
            case "Advanced.resetSettings":
                confirmAction(
                    title: NSLocalizedString("RESET_SETTINGS"),
                    message: NSLocalizedString("RESET_SETTINGS_TEXT")
                ) {
                    self.resetSettings()
                }
            case "Advanced.reset":
                confirmAction(
                    title: NSLocalizedString("RESET"),
                    message: NSLocalizedString("RESET_TEXT")
                ) {
                    (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
                    clearNetworkCache()
                    resetSettings()
                    Task {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.clearLibrary(context: context)
                            CoreDataManager.shared.clearManga(context: context)
                            CoreDataManager.shared.clearHistory(context: context)
                            CoreDataManager.shared.clearChapters(context: context)
                            CoreDataManager.shared.clearCategories(context: context)
                            CoreDataManager.shared.clearTracks(context: context)
                            try? context.save()
                        }
                        SourceManager.shared.clearSources()
                        SourceManager.shared.clearSourceLists()
                        NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateHistory"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
                        (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
                    }
                }
            default:
                break
        }
    }

    @ViewBuilder
    func pageContentHandler(_ key: String) -> (some View)? {
        if key == "Library.categories" {
            CategoriesView()
        } else if key == "Reader.tapZones" {
            TapZonesSelectView()
        } else if key == "Reader.upscalingModels" {
            UpscaleModelListView()
        } else if key == "Tracking" {
            SettingsTrackingView()
        } else if key == "About" {
            SettingsAboutView()
        } else if key == "SourceLists" {
            SourceListsView()
        } else if key == "Backups" {
            BackupsView().environmentObject(path)
        } else if key == "DownloadManager" {
            DownloadManagerView().environmentObject(path)
        }
    }

    @ViewBuilder
    func customContentHandler(_ setting: Setting) -> some View {
        if setting.key == "Library.defaultCategory" {
            let newSetting = {
                var setting = setting
                setting.value = .select(.init(
                    values: ["", "none"] + categories,
                    titles: [
                        NSLocalizedString("ALWAYS_ASK"), NSLocalizedString("NONE")
                    ] + categories
                ))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "Library.lockedCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: categories, authToOpen: true))
                return setting
            }()
            SettingView(setting: newSetting)
        } else if setting.key == "Library.excludedUpdateCategories" {
            let newSetting = {
                var setting = setting
                setting.value = .multiselect(.init(values: categories))
                return setting
            }()
            SettingView(setting: newSetting)
        }
    }
}

extension SettingsView {
    func confirmAction(
        title: String,
        message: String,
        continueActionName: String = NSLocalizedString("CONTINUE"),
        destructive: Bool = true,
        proceed: @escaping () -> Void
    ) {
        let alertView = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        let action = UIAlertAction(title: continueActionName, style: destructive ? .destructive : .default) { _ in proceed() }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))
        path.present(alertView, animated: true)
    }

    func clearNetworkCache() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            for record in records {
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
            }
        }
        // clear disk cache
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }
        // clear memory cache
        if let imageCache = ImagePipeline.shared.configuration.imageCache as? Nuke.ImageCache {
            imageCache.removeAll()
        }
    }

    func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }
}

// MARK: Searching
extension SettingsView {
    func search() {
        guard !searchText.isEmpty else {
            searchResult = nil
            return
        }
        var sections: [SettingSearchResult.Section] = []
        for rootSetting in Self.settings {
            guard case let .group(group) = rootSetting.value else { continue }

            var groupItems: [SettingPath] = []

            for setting in group.items {
                if case let .page(pageSetting) = setting.value {
                    let items = setting.search(for: searchText)
                    if !items.isEmpty {
                        sections.append(.init(icon: pageSetting.icon, header: setting.title, paths: items))
                    }
                } else {
                    if setting.title.contains(searchText) {
                        groupItems.append(.init(
                            key: setting.key,
                            title: setting.title,
                            paths: [setting.title],
                            setting: setting
                        ))
                    }
                }
            }

            if !groupItems.isEmpty {
                sections.append(.init(header: rootSetting.title.isEmpty ? nil : rootSetting.title, paths: groupItems))
            }
        }
        let result = SettingSearchResult(sections: sections)
        searchResult = result
    }

    func openSearchPage(for setting: SettingPath) {
        func findTargetPage(title: String) -> (Setting, PageSetting)? {
            for setting in Self.settings {
                if case let .group(group) = setting.value {
                    for item in group.items {
                        if case let .page(page) = item.value {
                            if item.title == title {
                                return (item, page)
                            }
                        }
                    }
                }
            }
            return nil
        }
        func findTargetSetting(title: String, in settings: [Setting]) -> Setting? {
            for setting in settings {
                if case let .group(group) = setting.value {
                    let result = findTargetSetting(title: title, in: group.items)
                    if let result {
                        return result
                    }
                } else if setting.title == title {
                    return setting
                }
            }
            return nil
        }
        guard
            let targetPageTitle = setting.paths.first,
            let (targetPageSetting, targetPage) = findTargetPage(title: targetPageTitle)
        else {
            return
        }
        let targetSetting = setting.paths[safe: 1].flatMap { targetSettingTitle in
            findTargetSetting(title: targetSettingTitle, in: targetPage.items)
        }

        let content = SettingPageDestination(
            setting: targetPageSetting,
            onChange: onSettingChange,
            value: targetPage,
            scrollTo: targetSetting
        )
        .settingPageContent(pageContentHandler)
        .settingCustomContent(customContentHandler)

        let controller = UIHostingController(rootView: content)
        let hasHeaderView = targetPage.icon != nil && targetPage.info != nil
        controller.title = hasHeaderView ? nil : targetPageSetting.title
        controller.navigationItem.largeTitleDisplayMode = .never
        path.push(controller)
    }
}

private extension Setting {
    func search(for text: String, currentPath: [String] = []) -> [SettingPath] {
        let path = currentPath + [title]

        func checkCurrent() -> [SettingPath] {
            if title.lowercased().contains(text.lowercased()) {
                return [.init(
                    key: key,
                    title: title,
                    paths: path,
                    setting: self
                )]
            }
            return []
        }

        switch value {
            case let .page(page):
                var results: [SettingPath] = checkCurrent()
                for item in page.items {
                    results.append(contentsOf: item.search(for: text, currentPath: path))
                }
                return results
            case let .group(group):
                var results: [SettingPath] = []
                for item in group.items {
                    results.append(contentsOf: item.search(for: text, currentPath: currentPath))
                }
                return results
            case .custom:
                // skip searching custom views
                return []
            default:
                return checkCurrent()
        }
    }
}
