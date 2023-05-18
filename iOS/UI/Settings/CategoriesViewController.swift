//
//  CategoriesViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/25/22.
//

import UIKit

class CategoriesViewController: UITableViewController {

    var categories: [String] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CATEGORIES", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addCategory)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        categories = CoreDataManager.shared.getCategoryTitles()

        tableView.setEditing(true, animated: false)
    }

    private func renameCategory(title: String, newTitle: String) async -> Bool {
        let success = await CoreDataManager.shared.container.performBackgroundTask { context in
            let success = CoreDataManager.shared.renameCategory(title: title, newTitle: newTitle, context: context)
            if !success { return false }
            do {
                try context.save()
                var locked = UserDefaults.standard.stringArray(forKey: "Library.lockedCategories") ?? []
                if let oldIndex = locked.firstIndex(of: title) {
                    locked[oldIndex] = newTitle
                    UserDefaults.standard.set(locked, forKey: "Library.lockedCategories")
                }
                return true
            } catch {
                LogManager.logger.error("CategoriesViewController.renameCategory(title: \(title)): \(error.localizedDescription)")
                return false
            }
        }
        if success {
            NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
        }
        return success
    }

     private func removeCategory(title: String) async -> Bool {
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
                LogManager.logger.error("CategoriesViewController.removeCategory(title: \(title)): \(error.localizedDescription)")
                return false
            }
        }
    }

    @objc func addCategory() {
        let alert = UIAlertController(
            title: NSLocalizedString("CATEGORY_ADD", comment: ""),
            message: NSLocalizedString("CATEGORY_ADD_TEXT", comment: ""),
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("CATEGORY_TITLE", comment: "")
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            guard let textField = alert.textFields?.first else { return }
            if let title = textField.text, !title.isEmpty, title.lowercased() != "none", !self.categories.contains(title) {
                Task {
                    await CoreDataManager.shared.container.performBackgroundTask { context in
                        CoreDataManager.shared.createCategory(title: title, context: context)
                        do {
                            try context.save()
                        } catch {
                            LogManager.logger.error("CategoriesViewController.addCategory: \(error.localizedDescription)")
                        }
                    }
                    self.categories.append(title)
                    self.tableView.insertRows(at: [IndexPath(row: self.categories.count - 1, section: 0)], with: .automatic)
                    NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
                }
            }
        })

        self.present(alert, animated: true)
    }
}

// MARK: - Table View Data Source
extension CategoriesViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        categories.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)

        cell.textLabel?.text = categories[indexPath.row]
        cell.selectionStyle = .none

        return cell
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let category = categories[sourceIndexPath.row]
        categories.remove(at: sourceIndexPath.row)
        categories.insert(category, at: destinationIndexPath.row)
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.moveCategory(title: category, position: destinationIndexPath.row, context: context)
                try? context.save()
            }
            NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let renameAction = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("RENAME", comment: "")
        ) { [weak self] _, _, completion in
            guard let self = self else { return }
            let category = self.categories[indexPath.row]

            let alert = UIAlertController(
                title: NSLocalizedString("RENAME_CATEGORY", comment: ""),
                message: NSLocalizedString("RENAME_CATEGORY_INFO", comment: ""),
                preferredStyle: .alert
            )

            alert.addTextField { textField in
                textField.placeholder = NSLocalizedString("CATEGORY_NAME", comment: "")
                textField.returnKeyType = .done
            }

            func fail() {
                let alert = UIAlertController(
                    title: NSLocalizedString("RENAME_CATEGORY_FAIL", comment: ""),
                    message: NSLocalizedString("RENAME_CATEGORY_FAIL_INFO", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                self.present(alert, animated: true)
                completion(false)
            }

            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                guard
                    let textField = alert.textFields?.first,
                    let newTitle = textField.text
                else {
                    completion(false)
                    return
                }
                if newTitle.lowercased() == "none" || self.categories.contains(newTitle) || newTitle.isEmpty {
                    fail()
                } else {
                    Task {
                        let success = await self.renameCategory(title: category, newTitle: newTitle)
                        if success {
                            self.categories[indexPath.row] = newTitle
                            tableView.reloadRows(at: [indexPath], with: .none)
                            completion(true)
                        } else {
                            fail()
                        }
                    }
                }
            })

            self.present(alert, animated: true)
        }
        renameAction.backgroundColor = .systemIndigo

        let deleteAction = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("DELETE", comment: "")
        ) { _, _, completion in
            Task {
                let category = self.categories[indexPath.row]
                let success = await self.removeCategory(title: category)
                if success {
                    self.categories.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                    NotificationCenter.default.post(name: Notification.Name("updateCategories"), object: nil)
                }
                completion(success)
            }
        }

        return UISwipeActionsConfiguration(actions: [deleteAction, renameAction])
    }
}
