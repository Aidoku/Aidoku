//
//  FilterGroupCreateView.swift
//  Aidoku
//
//  Created by Skitty on 2/27/26.
//

import SwiftUI

struct FilterGroupCreateView: View {
    // the filter group we're editing, if we're not creating a new one
    var editingGroupTitle: String?

    @State private var title: String = ""
    @State private var filters: [LibraryViewModel.LibraryFilter] = []
    @State private var isValid = false

    @State private var categories: [String] = []
    @State private var sourceKeys: [String] = []

    @State private var allCategoryAndGroupTitles: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Text(NSLocalizedString("NAME"))
                        TextField(editingGroupTitle ?? NSLocalizedString("NAME"), text: $title)
                    }
                }

                Section(NSLocalizedString("FILTERS")) {
                    ForEach(LibraryViewModel.FilterMethod.allCases, id: \.self) { method in
                        if method.isAvailable {
                            let state = filterState(for: method)
                            Button {
                                toggleFilter(method: method)
                            } label: {
                                HStack {
                                    Image(systemName: method.systemImageName)
                                        .frame(minWidth: 30)
                                        .foregroundStyle(.tint)
                                    Text(method.title)
                                    Spacer()
                                    switch state {
                                        case .included: Image(systemName: "checkmark").foregroundStyle(.tint)
                                        case .excluded: Image(systemName: "xmark").foregroundStyle(.tint)
                                        case .none: EmptyView()
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    DisclosureGroup {
                        ForEach(MangaContentRating.allCases, id: \.self) { rating in
                            let state = filterState(for: .contentRating, value: rating.stringValue)
                            Button {
                                toggleFilter(method: .contentRating, value: rating.stringValue)
                            } label: {
                                HStack {
                                    Text(rating.title)
                                    Spacer()
                                    switch state {
                                        case .included: Image(systemName: "checkmark").foregroundStyle(.tint)
                                        case .excluded: Image(systemName: "xmark").foregroundStyle(.tint)
                                        case .none: EmptyView()
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: LibraryViewModel.FilterMethod.contentRating.systemImageName)
                                .frame(minWidth: 30)
                                .foregroundStyle(.tint)
                            Text(LibraryViewModel.FilterMethod.contentRating.title)
                            Spacer()
                        }
                    }

                    DisclosureGroup {
                        ForEach(sourceKeys, id: \.self) { key in
                            let state = filterState(for: .source, value: key)
                            Button {
                                toggleFilter(method: .source, value: key)
                            } label: {
                                HStack {
                                    Text(SourceManager.shared.source(for: key)?.name ?? key)
                                    Spacer()
                                    switch state {
                                        case .included: Image(systemName: "checkmark").foregroundStyle(.tint)
                                        case .excluded: Image(systemName: "xmark").foregroundStyle(.tint)
                                        case .none: EmptyView()
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: LibraryViewModel.FilterMethod.source.systemImageName)
                                .frame(minWidth: 30)
                                .foregroundStyle(.tint)
                            Text(LibraryViewModel.FilterMethod.source.title)
                            Spacer()
                        }
                    }

                    DisclosureGroup {
                        ForEach(categories, id: \.self) { category in
                            let state = filterState(for: .category, value: category)
                            Button {
                                toggleFilter(method: .category, value: category)
                            } label: {
                                HStack {
                                    Text(category)
                                    Spacer()
                                    switch state {
                                        case .included: Image(systemName: "checkmark").foregroundStyle(.tint)
                                        case .excluded: Image(systemName: "xmark").foregroundStyle(.tint)
                                        case .none: EmptyView()
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: LibraryViewModel.FilterMethod.category.systemImageName)
                                .frame(minWidth: 30)
                                .foregroundStyle(.tint)
                            Text(LibraryViewModel.FilterMethod.category.title)
                            Spacer()
                        }
                    }
                }

                Section {
                    Button(NSLocalizedString("CLEAR_FILTERS")) {
                        filters = []
                    }
                    .disabled(filters.isEmpty)
                }
            }
            .scrollDismissesKeyboardImmediately()
            .navigationTitle(editingGroupTitle != nil ? NSLocalizedString("EDIT_FILTER_GROUP") : NSLocalizedString("CREATE_FILTER_GROUP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        Task {
                            await commit()
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: title) { _ in
                checkValidity()
            }
            .onChange(of: filters) { _ in
                if filters.isEmpty {
                    isValid = false
                } else if !isValid {
                    checkValidity()
                }
            }
            .task {
                await loadData()
            }
        }
    }
}

extension FilterGroupCreateView {
    func loadData() async {
        (
            categories,
            allCategoryAndGroupTitles,
            sourceKeys,
            filters
        ) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            let categories = CoreDataManager.shared.getCategoryTitles(context: context)
            let allCategoryAndGroupTitles = CoreDataManager.shared.getCategoryTitles(excludeFilterGroups: false, context: context)

            let request = LibraryMangaObject.fetchRequest()
            request.predicate = NSPredicate(format: "manga != nil")
            let libraryObjects = (try? context.fetch(request)) ?? []

            var sourceKeys: Set<String> = []
            for object in libraryObjects {
                guard let manga = object.manga else { continue }
                sourceKeys.insert(manga.sourceId)
            }

            var filters: [LibraryViewModel.LibraryFilter] = []
            if let editingGroupTitle {
                let request = CategoryObject.fetchRequest()
                request.predicate = NSPredicate(format: "title == %@", editingGroupTitle)
                request.fetchLimit = 1
                if
                    let category = (try? context.fetch(request))?.first,
                    let data = category.data as? Data,
                    let filterData = try? JSONDecoder().decode([LibraryViewModel.LibraryFilter].self, from: data)
                {
                    filters = filterData
                }
            }

            return (categories, allCategoryAndGroupTitles, sourceKeys.sorted(), filters)
        }

        // if we're editing a group, it's okay if it has the same title when checking validity
        if let editingGroupTitle, let index = allCategoryAndGroupTitles.firstIndex(of: editingGroupTitle) {
            allCategoryAndGroupTitles.remove(at: index)
        }

        // add any existing filtered items if they're missing from the data (e.g. removed source/category)
        for filter in filters {
            guard let value = filter.value else { continue }
            switch filter.type {
                case .source:
                    if !sourceKeys.contains(value) {
                        sourceKeys.append(value)
                    }
                case .category:
                    if !categories.contains(value) {
                        categories.append(value)
                    }
                default: break
            }
        }
    }

    func checkValidity() {
        var title = title.trim()
        if title.isEmpty {
            title = editingGroupTitle ?? ""
        }
        guard
            !filters.isEmpty,
            !title.isEmpty,
            title != "none",
            !allCategoryAndGroupTitles.contains(title)
        else {
            isValid = false
            return
        }
        isValid = true
    }
}

extension FilterGroupCreateView {
    func commit() async {
        guard isValid else { return }
        guard let data = try? JSONEncoder().encode(filters) else {
            LogManager.logger.error("Failed to encode filters data")
            return
        }
        let title = title.trim()
        if let editingGroupTitle {
            do {
                try await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                    let request = CategoryObject.fetchRequest()
                    request.predicate = NSPredicate(format: "title == %@", editingGroupTitle)
                    request.fetchLimit = 1
                    let result = try context.fetch(request)
                    guard let category = result.first else {
                        return
                    }
                    category.title = title.isEmpty ? editingGroupTitle : title
                    category.data = data as NSObject
                    try context.save()
                }
            } catch {
                LogManager.logger.error("Failed to edit filter group: \(error)")
                return
            }
        } else {
            do {
                try await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                    let category = CoreDataManager.shared.createCategory(title: title, group: true, context: context)
                    category.data = data as NSObject
                    try context.save()
                }
                NotificationCenter.default.post(name: .updateCategories, object: nil)
            } catch {
                LogManager.logger.error("Failed to create filter group: \(error)")
                return
            }
        }
        NotificationCenter.default.post(name: .updateCategories, object: nil)
    }
}

extension FilterGroupCreateView {
    func toggleFilter(method: LibraryViewModel.FilterMethod, value: String? = nil) {
        let filterIndex = filters.firstIndex(where: { $0.type == method && $0.value == value })
        if let filterIndex {
            if filters[filterIndex].exclude {
                filters.remove(at: filterIndex)
            } else {
                filters[filterIndex].exclude = true
            }
        } else {
            filters.append(.init(type: method, value: value, exclude: false))
        }
    }

    enum FilterState {
        case none
        case included
        case excluded
    }

    func filterState(for method: LibraryViewModel.FilterMethod, value: String? = nil) -> FilterState {
        if let filter = filters.first(where: { $0.type == method && $0.value == value }) {
            filter.exclude ? .excluded : .included
        } else {
            .none
        }
    }
}

#Preview {
    FilterGroupCreateView()
}
