//
//  AddSourceView.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import AidokuRunner
import SwiftUI
import UniformTypeIdentifiers

struct AddSourceView: View {
    let allExternalSources: [ExternalSourceInfo]

    @State private var externalSources: [SourceInfo] = []
    @State private var allSourcesInstalled: Bool = false

    @State private var hasLocalSourceInstalled: Bool
    @State private var loadedInitial = false
    @State private var importing = false
    @State private var searching = false
    @State private var searchText = ""
    @State private var showLocalSetup = false
    @State private var showKomgaSetup = false
    @State private var showKavitaSetup = false
    @State private var showSuwayomiSetup = false
    @State private var showImportFailAlert = false

    @State private var searchFocused: Bool? = false

    @Environment(\.dismiss) private var dismiss

    init(externalSources: [ExternalSourceInfo]) {
        allExternalSources = externalSources
        _hasLocalSourceInstalled = State(
            initialValue: CoreDataManager.shared.hasSource(key: LocalSourceRunner.sourceKey, context: CoreDataManager.shared.context)
        )
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                if !searching {
                    Section {
                        LargeButton {
                            importing = true
                        } label: {
                            HStack {
                                if importing {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Image(systemName: "folder.fill.badge.plus")
                                    Text(NSLocalizedString("IMPORT_SOURCE"))
                                }
                            }
                        }
                    }

                    builtInSources
                }

                Section {
                    if allExternalSources.isEmpty {
                        infoView(
                            title: NSLocalizedString("NO_EXTERNAL_SOURCES"),
                            subtitle: NSLocalizedString("NO_EXTERNAL_SOURCES_INFO")
                        )
                    } else if externalSources.isEmpty {
                        if allSourcesInstalled {
                            infoView(
                                title: NSLocalizedString("ALL_SOURCES_INSTALLED"),
                                subtitle: NSLocalizedString("ALL_SOURCES_INSTALLED_INFO"),
                            )
                        } else {
                            infoView(
                                title: NSLocalizedString("NO_AVAILABLE_SOURCES"),
                                subtitle: NSLocalizedString("NO_AVAILABLE_SOURCES_INFO"),
                            )
                        }
                    } else {
                        let filteredSources = if searchText.isEmpty {
                            externalSources
                        } else {
                            externalSources.filter {
                                ([$0.name.lowercased()] + ($0.altNames.map { $0.lowercased() }))
                                    .contains {
                                        $0.contains(searchText.lowercased())
                                    }
                            }
                        }
                        if filteredSources.isEmpty {
                            Text(NSLocalizedString("NO_RESULTS"))
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(filteredSources, id: \.sourceId) { source in
                                ExternalSourceTableCell(source: source, onInstall: {
                                    Task {
                                        let index = externalSources.firstIndex(of: source)
                                        if let index {
                                            let allInstalled = await checkAllSourcesInstalled()
                                            withAnimation {
                                                externalSources.remove(at: index)
                                                if externalSources.isEmpty {
                                                    allSourcesInstalled = allInstalled
                                                }
                                            }
                                        }
                                    }
                                })
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("EXTERNAL_SOURCES"))
                        Spacer()
                        if !externalSources.isEmpty, !searching {
                            Button {
                                searching = true
                                searchFocused = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .contentMarginsPlease(.top, 4)
            .customSearchable(
                text: $searchText,
                enabled: $searching,
                focused: $searchFocused,
                hidesNavigationBarDuringPresentation: false,
                hidesSearchBarWhenScrolling: false,
                onCancel: {
                    // task delays slightly to prevent sheet from closing
                    Task {
                        searching = false
                    }
                }
            )
            .environment(\.autocorrectionDisabled, true)
            .animation(.default, value: searchText)
            .animation(.default, value: searching)
            .sheet(isPresented: $importing) {
                DocumentPickerView(
                    allowedContentTypes: [
                        UTType(exportedAs: "app.aidoku.Aidoku.aix", conformingTo: .zip),
                        .init(filenameExtension: "aix")!
                    ],
                    onDocumentsPicked: { urls in
                        guard let url = urls.first else {
                            return
                        }
                        Task {
                            let result = await SourceManager.shared.importSource(from: url)
                            if result == nil {
                                showImportFailAlert = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .alert(NSLocalizedString("IMPORT_FAIL"), isPresented: $showImportFailAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("SOURCE_IMPORT_FAIL_TEXT"))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !allExternalSources.isEmpty {
                        AddSourceFilterMenu()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("ADD_SOURCE"))
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .filterExternalSources)) { _ in
                Task {
                    await reload()
                }
            }
        }
        .interactiveDismissDisabled(searching)
        .onReceive(NotificationCenter.default.publisher(for: .sourceLoaded)) { output in
            if let key = output.object as? String, key == LocalSourceRunner.sourceKey {
                hasLocalSourceInstalled = true
            }
        }
        .task {
            guard !loadedInitial else { return }
            await reload()
            loadedInitial = true
        }
    }

    func reload() async {
        let result = await filterExternalSources()
        withAnimation {
            externalSources = result.0
            allSourcesInstalled = result.allSourcesInstalled
        }
    }

    var builtInSources: some View {
        Section(NSLocalizedString("BUILT_IN_SOURCES")) {
//            if !SourceManager.shared.sources.contains(where: { $0.key == "demo" }) {
//                ExternalSourceTableCell(
//                    source: .init(
//                        sourceId: "demo",
//                        name: "Demo Source",
//                        languages: ["multi"],
//                        version: 1,
//                        contentRating: .safe
//                    ),
//                    onGet: {
//                        let config = CustomSourceConfig.demo
//                        let source = config.toSource()
//
//                        // add to coredata
//                        await CoreDataManager.shared.container.performBackgroundTask { context in
//                            let result = CoreDataManager.shared.createSource(source: source, context: context)
//                            result.customSource = config.encode() as NSObject
//                            try? context.save()
//                        }
//
//                        SourceManager.shared.sources.append(source)
//                        SourceManager.shared.sortSources()
//
//                        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
//
//                        dismiss()
//
//                        return true
//                    }
//                )
//            }

            if !hasLocalSourceInstalled {
                ExternalSourceTableCell(
                    source: .init(
                        sourceId: LocalSourceRunner.sourceKey,
                        name: NSLocalizedString("LOCAL_FILES"),
                        languages: ["multi"],
                        version: 1,
                        contentRating: .safe
                    ),
                    subtitle: NSLocalizedString("LOCAL_FILES_TAGLINE"),
                    onGet: {
                        showLocalSetup = true
                        return true
                    }
                )
                .background(NavigationLink("", destination: LocalSetupView(), isActive: $showLocalSetup).hidden())
            }

            ExternalSourceTableCell(
                source: .init(
                    sourceId: "komga",
                    name: NSLocalizedString("KOMGA"),
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("KOMGA_TAGLINE"),
                onGet: {
                    showKomgaSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: KomgaSetupView(), isActive: $showKomgaSetup).hidden())

            ExternalSourceTableCell(
                source: .init(
                    sourceId: "kavita",
                    name: NSLocalizedString("KAVITA"),
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("KAVITA_TAGLINE"),
                onGet: {
                    showKavitaSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: KavitaSetupView(), isActive: $showKavitaSetup).hidden())

            ExternalSourceTableCell(
                source: .init(
                    sourceId: "suwayomi",
                    name: NSLocalizedString("SUWAYOMI"),
                    languages: ["multi"],
                    version: 1,
                    contentRating: .safe
                ),
                subtitle: NSLocalizedString("SUWAYOMI_TAGLINE"),
                onGet: {
                    showSuwayomiSetup = true
                    return true
                }
            )
            .background(NavigationLink("", destination: SuwayomiSetupView(), isActive: $showSuwayomiSetup).hidden())
        }
    }

    func infoView(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .fontWeight(.medium)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    func checkAllSourcesInstalled() async -> Bool {
        let installedSources = await  SourceManager.shared.getSourceInfos(sorted: false)
        return !allExternalSources.contains { source in
            !installedSources.contains(where: { $0.sourceId == source.id })
        }
    }

    func filterExternalSources() async -> ([SourceInfo], allSourcesInstalled: Bool) {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return ([], true) }
        let appVersion = SemanticVersion(appVersionString)
        let selectedLanguages = AppSettings.browse.languages.get()
        let contentRatings = AppSettings.browse.contentRatings.get()

        var allSourcesInstalled = true

        let installedSources = await SourceManager.shared.getSourceInfos()
        let result = allExternalSources
            .compactMap { info -> SourceInfo? in
                // strip installed sources from external list
                if installedSources.contains(where: { $0.sourceId == info.id }) {
                    return nil
                }
                // this source isn't installed
                allSourcesInstalled = false
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
                // hide unselected content ratings
                let contentRating = info.resolvedContentRating
                if !contentRatings.contains(contentRating) {
                    return nil
                }
                // hide unselected languages
                if !selectedLanguages.contains(where: { info.languages?.contains($0) ?? (info.lang == $0) }) {
                    return nil
                }
                return info.toInfo()
            }
            .sorted { lhs, rhs in
                let languageOrder = SourceLanguage.compare(lhs.languages, rhs.languages)
                if languageOrder != .orderedSame {
                    return languageOrder == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return (result, allSourcesInstalled)
    }
}
