//
//  CategorySelectViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/25/22.
//

import UIKit

class CategorySelectViewController: UITableViewController {

    let manga: Manga

    var categories: [String] = []
    var selectedCategories: [String] = []

    var inLibrary: Bool {
        DataManager.shared.libraryContains(manga: manga)
    }

    init(manga: Manga) {
        self.manga = manga
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("CATEGORIES", comment: "")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(add))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        categories = DataManager.shared.getCategories()
        if inLibrary {
            selectedCategories = DataManager.shared.getCategories(for: manga)
        }
    }

    @objc func close() {
        dismiss(animated: true)
    }

    func setCategories() {
        if !selectedCategories.isEmpty {
            DataManager.shared.setMangaCategories(manga: manga, categories: selectedCategories)
        }
        close()
    }

    @objc func add() {
        if inLibrary {
            setCategories()
        } else {
            DataManager.shared.addToLibrary(manga: manga) {
                self.setCategories()
            }
        }
    }
}

// MARK: - Table View Data Source
extension CategorySelectViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        categories.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)

        cell.textLabel?.text = categories[indexPath.row]
        if selectedCategories.contains(categories[indexPath.row]) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath) {
            if cell.accessoryType == .checkmark {
                cell.accessoryType = .none
                selectedCategories.removeAll(where: { $0 == categories[indexPath.row] })
            } else {
                cell.accessoryType = .checkmark
                selectedCategories.append(categories[indexPath.row])
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
