//
//  CategorySelectViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/25/22.
//

import UIKit
import AidokuRunner

class CategorySelectViewController: UITableViewController {
    let manga: AidokuRunner.Manga

    var categories: [String] = []
    var selectedCategories: [String] = []

    init(manga: AidokuRunner.Manga) {
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(addCategory))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                self.categories = CoreDataManager.shared.getCategories(context: context).map {
                    $0.title ?? ""
                }
                let inLibrary = CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceKey,
                    mangaId: self.manga.key,
                    context: context
                )
                if inLibrary {
                    self.selectedCategories = CoreDataManager.shared.getCategories(
                        sourceId: self.manga.sourceKey,
                        mangaId: self.manga.key,
                        context: context
                    )
                    .compactMap { $0.title }
                }
            }
            tableView.reloadData()
        }
    }

    @objc func close() {
        dismiss(animated: true)
    }

    @objc func addCategory() {
        close()
        Task {
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceKey,
                    mangaId: self.manga.key,
                    context: context
                )
            }
            if !inLibrary {
                await MangaManager.shared.addToLibrary(
                    sourceId: manga.sourceKey,
                    manga: manga,
                    chapters: manga.chapters ?? []
                )
            }
            await MangaManager.shared.setCategories(
                sourceId: manga.sourceKey,
                mangaId: manga.key,
                categories: selectedCategories
            )
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
