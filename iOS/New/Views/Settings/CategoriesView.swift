//
//  CategoriesView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct CategoriesView: View {
    @State private var categories: [String]

    @State private var categoryTitle: String = ""
    @State private var targetRenameCategory: String?
    @State private var showAddAlert = false
    @State private var showRenameAlert = false
    @State private var showRenameFailedAlert = false

    init() {
        self._categories = State(initialValue: CoreDataManager.shared.getCategoryTitles())
    }

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .swipeActions {
                        Button(role: .destructive) {
                            onDelete(at: IndexSet(integer: categories.firstIndex(of: category)!))
                        } label: {
                            Label(NSLocalizedString("DELETE"), systemImage: "trash")
                        }
                        Button {
                            targetRenameCategory = category
                            showRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("RENAME"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
            }
            .onDelete(perform: onDelete)
            .onMove(perform: onMove)
        }
        .animation(.default, value: categories)
        .environment(\.editMode, Binding.constant(.active))
        .navigationTitle(NSLocalizedString("CATEGORIES"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("CATEGORY_ADD"), isPresented: $showAddAlert) {
            TextField(NSLocalizedString("CATEGORY_TITLE"), text: $categoryTitle)
                .autocorrectionDisabled()
                .submitLabel(.done)
            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                categoryTitle = ""
            }
            Button(NSLocalizedString("OK")) {
                addCategory(title: categoryTitle)
                categoryTitle = ""
            }
        } message: {
            Text(NSLocalizedString("CATEGORY_ADD_TEXT"))
        }
        .alert(NSLocalizedString("RENAME_CATEGORY"), isPresented: $showRenameAlert) {
            TextField(NSLocalizedString("CATEGORY_NAME"), text: $categoryTitle)
                .autocorrectionDisabled()
                .submitLabel(.done)
            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                categoryTitle = ""
            }
            Button(NSLocalizedString("OK")) {
                if let targetRenameCategory {
                    renameCategory(title: targetRenameCategory, newTitle: categoryTitle)
                }
                categoryTitle = ""
            }
        } message: {
            Text(NSLocalizedString("RENAME_CATEGORY_INFO"))
        }
        .alert(NSLocalizedString("RENAME_CATEGORY_FAIL"), isPresented: $showRenameFailedAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("RENAME_CATEGORY_FAIL_INFO"))
        }
    }

    func onDelete(at offsets: IndexSet) {
        Task {
            var removedOffsets: IndexSet = []
            for offset in offsets {
                let category = categories[offset]
                let success = await self.removeCategory(title: category)
                if success {
                    removedOffsets.insert(offset)
                }
            }
            categories.remove(atOffsets: removedOffsets)
            NotificationCenter.default.post(name: .updateCategories, object: nil)
        }
    }

    func onMove(from source: IndexSet, to destination: Int) {
        for offset in source {
            let category = categories[offset]
            let position = offset < destination ? destination - 1 : destination
            CoreDataManager.shared.moveCategory(title: category, position: position)
        }
        categories.move(fromOffsets: source, toOffset: destination)
        CoreDataManager.shared.save()
        NotificationCenter.default.post(name: .updateCategories, object: nil)
    }
}

extension CategoriesView {
    func addCategory(title: String) {
        if !title.isEmpty, title.lowercased() != "none", !categories.contains(title) {
            Task {
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.createCategory(title: title, context: context)
                    do {
                        try context.save()
                    } catch {
                        LogManager.logger.error("Failed to save data when adding category: \(error)")
                    }
                }
                categories.append(title)
                NotificationCenter.default.post(name: .updateCategories, object: nil)
            }
        }
    }

    func removeCategory(title: String) async -> Bool {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeCategory(title: title, context: context)
            do {
                try context.save()
                var locked = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []
                if let oldIndex = locked.firstIndex(of: title) {
                    locked.remove(at: oldIndex)
                    UserDefaults.standard.set(locked, forKey: "Library.lockedCategories")
                }
                return true
            } catch {
                LogManager.logger.error("CategoriesView.removeCategory(title: \(title)): \(error)")
                return false
            }
        }
    }

    func renameCategory(title: String, newTitle: String) {
        if newTitle.lowercased() == "none" || self.categories.contains(newTitle) || newTitle.isEmpty {
            showRenameFailedAlert = true
        } else {
            Task {
                let success = await CoreDataManager.shared.container.performBackgroundTask { context in
                    let success = CoreDataManager.shared.renameCategory(title: title, newTitle: newTitle, context: context)
                    guard success else { return false }
                    do {
                        try context.save()
                        var locked = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []
                        if let oldIndex = locked.firstIndex(of: title) {
                            locked[oldIndex] = newTitle
                            UserDefaults.standard.set(locked, forKey: "Library.lockedCategories")
                        }
                        return true
                    } catch {
                        LogManager.logger.error("CategoriesView.renameCategory(title: \(title)): \(error)")
                        return false
                    }
                }
                if success {
                    categories = CoreDataManager.shared.getCategoryTitles()
                    NotificationCenter.default.post(name: .updateCategories, object: nil)
                } else {
                    showRenameFailedAlert = true
                }
            }
        }
    }

}
