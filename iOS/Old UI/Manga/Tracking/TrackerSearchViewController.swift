//
//  TrackerSearchViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/21/22.
//

import SwiftUI

class TrackerSearchViewController: UITableViewController {

    let tracker: Tracker
    let manga: Manga

    var results: [TrackSearchItem] = []
    var query: String?
    var selectedIndex: Int?

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(tracker: Tracker, manga: Manga) {
        self.tracker = tracker
        self.manga = manga
        self.query = manga.title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("TRACK", comment: ""),
            style: .done,
            target: self,
            action: #selector(track)
        )
        updateNavbar()

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.text = query
        searchController.searchBar.showsCancelButton = false
        navigationItem.searchController = searchController

        navigationItem.hidesSearchBarWhenScrolling = false

        tableView.register(TrackerSearchTableViewCell.self, forCellReuseIdentifier: "TrackerSearchTableViewCell")
        tableView.separatorStyle = .none

        activityIndicator.hidesWhenStopped = true
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            results = await tracker.search(for: manga)
            await MainActor.run {
                activityIndicator.stopAnimating()
                tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
            }
        }
    }

    func updateNavbar() {
        navigationItem.rightBarButtonItem?.isEnabled = selectedIndex != nil && results.count > selectedIndex ?? 0
    }

    @objc func close() {
        dismiss(animated: true)
    }

    @objc func track() {
        let result = results[selectedIndex ?? 0]
        Task { @MainActor in
            let hasReadChapters = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasHistory(sourceId: self.manga.sourceId, mangaId: self.manga.id, context: context)
            }
            await tracker.register(trackId: result.id, hasReadChapters: hasReadChapters)
            await TrackerManager.shared.saveTrackItem(item: TrackItem(
                id: result.id,
                trackerId: tracker.id,
                sourceId: manga.sourceId,
                mangaId: manga.id,
                title: result.title
            ))
        }
        dismiss(animated: true)
    }
}

extension TrackerSearchViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TrackerSearchTableViewCell", for: indexPath) as? TrackerSearchTableViewCell
        guard let cell = cell else { return UITableViewCell() }
        guard indexPath.row < results.count else {
            return cell
        }
        cell.item = results[indexPath.row]
        cell.accessoryType = selectedIndex == indexPath.row ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let index = selectedIndex, let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) {
            cell.accessoryType = .none
        }
        if let cell = tableView.cellForRow(at: indexPath) {
            if selectedIndex == indexPath.row {
                cell.accessoryType = .none
                selectedIndex = nil
            } else {
                cell.accessoryType = .checkmark
                selectedIndex = indexPath.row
            }
        }
        updateNavbar()
    }
}

extension TrackerSearchViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard searchBar.text != query else { return }
        query = searchBar.text
        results = []
        selectedIndex = nil
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
        updateNavbar()
        if let query = query {
            activityIndicator.startAnimating()
            Task {
                results = await tracker.search(title: query)
                await MainActor.run {
                    activityIndicator.stopAnimating()
                    tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
                }
            }
        }
    }
}

struct TrackerSearchNavigationController: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    let tracker: Tracker
    let manga: Manga

    func makeUIViewController(context: Context) -> UIViewControllerType {
        UINavigationController(rootViewController: TrackerSearchViewController(tracker: tracker, manga: manga))
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}
