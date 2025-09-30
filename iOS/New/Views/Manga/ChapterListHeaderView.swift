//
//  ChapterListHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 4/23/25.
//

import SwiftUI
import AidokuRunner

struct ChapterListHeaderView: View {
    private let chapterCount: Int?

    @Binding var sortOption: ChapterSortOption
    @Binding var sortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var displayMode: ChapterTitleDisplayMode

    private var showMenu: Bool = false
    private var languages: [String] = []
    private var scanlators: [String] = []
    private var mangaUniqueKey: String

    init(
        allChapters: [AidokuRunner.Chapter]? = nil,
        filteredChapters: [AidokuRunner.Chapter]? = nil,
        sortOption: Binding<ChapterSortOption>,
        sortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        displayMode: Binding<ChapterTitleDisplayMode>,
        mangaUniqueKey: String
    ) {
        self.chapterCount = filteredChapters?.count
        self._sortOption = sortOption
        self._sortAscending = sortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._displayMode = displayMode
        self.mangaUniqueKey = mangaUniqueKey

        if let allChapters, !allChapters.isEmpty {
            var languages: Set<String> = []
            var scanlators: Set<String> = []
            for chapter in allChapters {
                for scanlator in chapter.scanlators ?? [] {
                    scanlators.insert(scanlator)
                }
                if let lang = chapter.language {
                    languages.insert(lang)
                }
            }
            self.languages = languages.sorted()
            self.scanlators = scanlators.sorted()
            self.showMenu = true
        }
    }

    var body: some View {
        HStack {
            let text = if let chapterCount {
                if chapterCount == 0 {
                    NSLocalizedString("NO_CHAPTERS")
                } else if chapterCount == 1 {
                    NSLocalizedString("1_CHAPTER").lowercased()
                } else {
                    String(format: NSLocalizedString("%i_CHAPTERS"), chapterCount).lowercased()
                }
            } else {
                NSLocalizedString("LOADING_ELLIPSIS")
            }
            Text(text)
                .font(.headline)
                .padding(.vertical, 10)
                .transition(.scale) // for some reason this makes it animate correctly
                .id("chapters")

            Spacer()

            if showMenu {
                menu
            }
        }
    }

    var menu: some View {
        Menu {
            Section(NSLocalizedString("SORT_BY")) {
                ForEach(ChapterSortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = false
                        }
                    } label: {
                        Label {
                            Text(option.stringValue)
                        } icon: {
                            if sortOption == option {
                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
            Section(NSLocalizedString("FILTER_BY")) {
                ForEach(ChapterFilterMethod.allCases, id: \.self) { option in
                    let filterIdx = filters.firstIndex(where: { $0.type == option })
                    Button {
                        if let filterIdx {
                            if filters[filterIdx].exclude {
                                filters.remove(at: filterIdx)
                            } else {
                                filters[filterIdx].exclude = true
                            }
                        } else {
                            filters.append(ChapterFilterOption(type: option, exclude: false))
                        }
                    } label: {
                        Label {
                            Text(option.stringValue)
                        } icon: {
                            if let filterIdx, filters[filterIdx].exclude {
                                Image(systemName: "xmark")
                            } else if filterIdx != nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if languages.count > 1 {
                    Menu(NSLocalizedString("LANGUAGE")) {
                        ForEach(languages, id: \.self) { lang in
                            Button {
                                let langValue = langFilter == lang ? nil : lang
                                langFilter = langValue
                            } label: {
                                Label {
                                    Text(Locale.current.localizedString(forIdentifier: lang) ?? lang)
                                } icon: {
                                    if langFilter == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if scanlators.count > 1 {
                    Menu(NSLocalizedString("SCANLATOR")) {
                        ForEach(scanlators, id: \.self) { scanlator in
                            Button {
                                if let filterIndex = scanlatorFilter.firstIndex(of: scanlator) {
                                    scanlatorFilter.remove(at: filterIndex)
                                } else {
                                    scanlatorFilter.append(scanlator)
                                }
                            } label: {
                                Label {
                                    Text(scanlator.isEmpty ? NSLocalizedString("NO_SCANLATOR") : scanlator)
                                } icon: {
                                    if scanlatorFilter.contains(scanlator) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section(NSLocalizedString("TITLE_DISPLAY_MODE")) {
                ForEach(ChapterTitleDisplayMode.allCases, id: \.rawValue) { mode in
                    Button {
                        displayMode = mode
                        let key = "Manga.chapterDisplayMode.\(mangaUniqueKey)"
                        if mode == .default {
                            UserDefaults.standard.removeObject(forKey: key)
                        } else {
                            UserDefaults.standard.set(mode.rawValue, forKey: key)
                        }
                    } label: {
                        Label {
                            Text(mode.localizedTitle)
                        } icon: {
                            if displayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 21, weight: .regular))
        }
        .foregroundStyle(.tint)
    }
}
