//
//  AddToCategoryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/3/23.
//

import UIKit

class AddToCategoryViewController: BaseTableViewController {

    let manga: [MangaInfo]
    var disabledCategories: [String] // categories disabled for selection

    var categories: [String] = []
    var selectedCategories: [String] = [] // for multiselect

    var multiselect: Bool = false // if enabled, can select multiple

    lazy var dataSource = makeDataSource()

    override var tableViewStyle: UITableView.Style {
        .plain
    }

    init(manga: [MangaInfo], disabledCategories: [String] = []) {
        self.manga = manga
        self.disabledCategories = disabledCategories
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        super.configure()

        title = multiselect
            ? NSLocalizedString("ADD_TO_CATEGORIES", comment: "")
            : NSLocalizedString("ADD_TO_CATEGORY", comment: "")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(close)
        )
        if multiselect {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(done)
            )
        }

        tableView.dataSource = dataSource
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        Task {
            categories = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getCategories(context: context).map { $0.title ?? "" }
            }
            updateDataSource()
        }
    }

    @objc func close() {
        dismiss(animated: true)
    }

    @objc func done() {
        close()
        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                for manga in self.manga {
                    CoreDataManager.shared.addCategoriesToManga(
                        sourceId: manga.sourceId,
                        mangaId: manga.mangaId,
                        categories: self.selectedCategories,
                        context: context
                    )
                    try? context.save()
                }
            }
            NotificationCenter.default.post(name: NSNotification.Name("updateMangaCategories"), object: manga)
        }
    }
}

// MARK: - Table View Delegate
extension AddToCategoryViewController {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath), let category = dataSource.itemIdentifier(for: indexPath) {
            if disabledCategories.contains(category) {
                return
            }
            if multiselect {
                if cell.accessoryType == .checkmark {
                    cell.accessoryType = .none
                    selectedCategories.removeAll { $0 == category }
                } else {
                    cell.accessoryType = .checkmark
                    selectedCategories.append(category)
                }
            } else {
                selectedCategories.append(category)
                done()
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Data Source
extension AddToCategoryViewController {

    enum Section: Int {
        case regular
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, String> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, category in
            guard let self = self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            cell.textLabel?.text = category
            if self.multiselect {
                if self.selectedCategories.contains(self.categories[indexPath.row]) {
                    cell.accessoryType = .checkmark
                } else {
                    cell.accessoryType = .none
                }
            }
            if self.disabledCategories.contains(category) {
                cell.selectionStyle = .none
                cell.textLabel?.textColor = .secondaryLabel
            }
            return cell
        }
    }

    func updateDataSource() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()

        snapshot.appendSections([.regular])
        snapshot.appendItems(categories)

        dataSource.apply(snapshot)
    }
}
