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

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addCategory))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        categories = DataManager.shared.getCategories()

        tableView.setEditing(true, animated: false)
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
            if let title = textField.text, !title.isEmpty, title.lowercased() != "none" {
                DataManager.shared.addCategory(title: title)
                self.categories.append(title)
                self.tableView.insertRows(at: [IndexPath(row: self.categories.count - 1, section: 0)], with: .automatic)
            }
        })

        self.present(alert, animated: true, completion: nil)
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

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            DataManager.shared.deleteCategory(title: categories[indexPath.row])
            categories.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let category = categories[sourceIndexPath.row]
        categories.remove(at: sourceIndexPath.row)
        categories.insert(category, at: destinationIndexPath.row)
        DataManager.shared.moveCategory(title: category, toPosition: destinationIndexPath.row)
    }
}
