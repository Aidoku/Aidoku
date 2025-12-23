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
                            showRenamePrompt(targetRenameCategory: category)
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
                    showAddPrompt()
                } label: {
                    Image(systemName: "plus")
                }
            }
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
        let sourceIndices = source.sorted()
        var adjustedDestination = destination

        // if moving down, adjust destination for each item removed before it
        // e.g. moving [0] to the end of a three item list will have destination 3,
        //      but we need to move it to index 2
        if let first = sourceIndices.first, first < destination {
            adjustedDestination -= sourceIndices.count
        }

        for offset in sourceIndices.reversed() {
            let category = categories[offset]
            CoreDataManager.shared.moveCategory(title: category, toPosition: adjustedDestination)
        }

        categories = CoreDataManager.shared.getCategoryTitles()
        CoreDataManager.shared.save()
        NotificationCenter.default.post(name: .updateCategories, object: nil)
    }

    func showAddPrompt() {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("CATEGORY_ADD"),
            message: NSLocalizedString("CATEGORY_ADD_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    addCategory(title: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("CATEGORY_TITLE")
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }

    func showRenamePrompt(targetRenameCategory: String) {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("RENAME_CATEGORY"),
            message: NSLocalizedString("RENAME_CATEGORY_INFO"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    renameCategory(title: targetRenameCategory, newTitle: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("CATEGORY_NAME")
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
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
