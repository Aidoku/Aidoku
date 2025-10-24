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

    @State private var externalSources: [SourceInfo2] = []
    @State private var allSourcesInstalled: Bool = false

    @State private var importing = false
    @State private var searching = false
    @State private var searchText = ""
    @State private var showLocalSetup = false
    @State private var showKomgaSetup = false
    @State private var showKavitaSetup = false
    @State private var showImportFailAlert = false
    @State private var showLanguageSelectSheet = false

    @State private var searchFocused: Bool? = false

    @Environment(\.dismiss) private var dismiss

    init(externalSources: [ExternalSourceInfo]) {
        allExternalSources = externalSources

        let result = filterExternalSources()
        _externalSources = State(initialValue: result.0)
        _allSourcesInstalled = State(initialValue: result.allSourcesInstalled)
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
                                    let index = externalSources.firstIndex(of: source)
                                    if let index {
                                        withAnimation {
                                            externalSources.remove(at: index)
                                            if externalSources.isEmpty {
                                                allSourcesInstalled = checkAllSourcesInstalled()
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
                            let result = try? await SourceManager.shared.importSource(from: url)
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
            .sheet(isPresented: $showLanguageSelectSheet) {
                AddSourceFilterView()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !allExternalSources.isEmpty {
                        Button {
                            showLanguageSelectSheet = true
                        } label: {
                            if #available(iOS 26.0, *) {
                                Image(systemName: "line.3.horizontal.decrease")
                            } else {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("ADD_SOURCE"))
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: .filterExternalSources)) { _ in
                let result = filterExternalSources()
                externalSources = result.0
                allSourcesInstalled = result.allSourcesInstalled
            }
        }
        .interactiveDismissDisabled(searching)
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

            if !SourceManager.shared.sources.contains(where: { $0.key == LocalSourceRunner.sourceKey }) {
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

    func checkAllSourcesInstalled() -> Bool {
        let installedSources = SourceManager.shared.sources.map { $0.toInfo() }
        return !allExternalSources.contains { source in
            !installedSources.contains(where: { $0.sourceId == source.id })
        }
    }

    func filterExternalSources() -> ([SourceInfo2], allSourcesInstalled: Bool) {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return ([], true) }
        let appVersion = SemanticVersion(appVersionString)
        let selectedLanguages = UserDefaults.standard.stringArray(forKey: "Browse.languages") ?? []
        let contentRatings = (UserDefaults.standard.stringArray(forKey: "Browse.contentRatings") ?? [])
            .compactMap { SourceContentRating(stringValue: $0) }

        var allSourcesInstalled = true

        let installedSources = SourceManager.shared.sources.map { $0.toInfo() }
        let result = allExternalSources
            .compactMap { info -> SourceInfo2? in
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
                if !contentRatings.contains(where: { $0 == contentRating }) {
                    return nil
                }
                // hide unselected languages
                if !selectedLanguages.contains(where: { info.languages?.contains($0) ?? (info.lang == $0) }) {
                    return nil
                }
                return info.toInfo()
            }
            // sort first by name, then by language
            .sorted { $0.name < $1.name }
            .sorted {
                let lhsLang = $0.languages.count == 1 ? $0.languages[0] : "multi"
                let rhsLang = $1.languages.count == 1 ? $1.languages[0] : "multi"
                let lhs = SourceManager.languageCodes.firstIndex(of: lhsLang) ?? Int.max
                let rhs = SourceManager.languageCodes.firstIndex(of: rhsLang) ?? Int.max
                return lhs < rhs
            }
        return (result, allSourcesInstalled)
    }
}
