//
//  FilterGroupsView.swift
//  Aidoku
//
//  Created by Skitty on 2/25/26.
//

import SwiftUI

struct FilterGroupsView: View {
    @State private var groups: [FilterGroup]

    @State private var editingGroupTitle: EditingGroupTitle?
    @State private var showCreateSheet = false
    @State private var showRenameFailedAlert = false

    struct EditingGroupTitle: Identifiable {
        var id: String { value}
        let value: String
    }

    private enum SheetID: String {
        case create
    }

    @Namespace private var transitionNamespace

    init() {
        let groups = CoreDataManager.shared.getFilterGroups()
        self._groups = State(initialValue: groups)
    }

    var body: some View {
        List {
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                Text(group.title)
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(at: IndexSet(integer: index))
                        } label: {
                            Label(NSLocalizedString("DELETE"), systemImage: "trash")
                        }
                        Button {
                            editingGroupTitle = .init(value: group.title)
                        } label: {
                            Label(NSLocalizedString("EDIT"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
            }
            .onDelete(perform: onDelete)
            .onMove(perform: onMove)
        }
        .animation(.default, value: groups)
        .environment(\.editMode, Binding.constant(.active))
        .navigationTitle(NSLocalizedString("FILTER_GROUPS"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .matchedTransitionSourcePlease(id: SheetID.create, in: transitionNamespace)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            FilterGroupCreateView()
                .navigationTransitionZoom(sourceID: SheetID.create, in: transitionNamespace)
        }
        .sheet(item: $editingGroupTitle) { editingGroupTitle in
            FilterGroupCreateView(editingGroupTitle: editingGroupTitle.value)
        }
        .alert(NSLocalizedString("RENAME_CATEGORY_FAIL"), isPresented: $showRenameFailedAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("RENAME_CATEGORY_FAIL_INFO"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateCategories)) { _ in
            groups = CoreDataManager.shared.getFilterGroups()
        }
    }

    func onDelete(at offsets: IndexSet) {
        Task {
            var removedOffsets: IndexSet = []
            for offset in offsets {
                let group = groups[offset]
                let success = await self.removeGroup(title: group.title)
                if success {
                    removedOffsets.insert(offset)
                }
            }
            groups.remove(atOffsets: removedOffsets)
            NotificationCenter.default.post(name: .updateCategories, object: nil)
        }
    }

    func onMove(from source: IndexSet, to destination: Int) {
        let sourceIndices = source.sorted()
        var adjustedDestination = destination

        // if moving down, adjust destination for each item removed before it
        // e.g. moving [0] to the end of a three item list will have destination 3,
        //      but we need to move it to index 2
        if let first = sourceIndices.first, first < destination {
            adjustedDestination -= sourceIndices.count
        }

        for offset in sourceIndices.reversed() {
            let group = groups[offset]
            CoreDataManager.shared.moveCategory(title: group.title, toPosition: adjustedDestination)
        }

        groups = CoreDataManager.shared.getFilterGroups()
        CoreDataManager.shared.save()
        NotificationCenter.default.post(name: .updateCategories, object: nil)
    }
}

extension FilterGroupsView {
    func removeGroup(title: String) async -> Bool {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeCategory(title: title, context: context)
            do {
                try context.save()
                return true
            } catch {
                LogManager.logger.error("FilterGroupsView.removeGroup(title: \(title)): \(error)")
                return false
            }
        }
    }

    func renameGroup(title: String, newTitle: String) {
        if newTitle.lowercased() == "none" || self.groups.map({ $0.title }).contains(newTitle) || newTitle.isEmpty {
            showRenameFailedAlert = true
        } else {
            Task {
                let success = await CoreDataManager.shared.container.performBackgroundTask { context in
                    let success = CoreDataManager.shared.renameCategory(title: title, newTitle: newTitle, context: context)
                    guard success else { return false }
                    do {
                        try context.save()
                        return true
                    } catch {
                        LogManager.logger.error("FilterGroupsView.renameGroup(title: \(title), newTitle: \(newTitle)): \(error)")
                        return false
                    }
                }
                if success {
                    groups = CoreDataManager.shared.getFilterGroups()
                    NotificationCenter.default.post(name: .updateCategories, object: nil)
                } else {
                    showRenameFailedAlert = true
                }
            }
        }
    }
}
