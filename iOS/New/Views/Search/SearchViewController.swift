//
//  SearchViewController.swift
//  Aidoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import Combine
import SwiftUI

class SearchViewController: UIViewController {
    private let viewModel = SearchContentView.ViewModel()
    private let searchController: UISearchController = .init(searchResultsController: nil)

    private var cancellables = Set<AnyCancellable>()

    private var sources: [AidokuRunner.Source] = [] {
        didSet {
            viewModel.sources = sources
            loadSourceLanguages()
        }
    }
    private var searchText: String = "" {
        didSet {
            updateHostingControllers()
        }
    }
    private var searchCommitToggle: Bool = false {
        didSet {
            updateHostingControllers()
        }
    }
    private var filters: [FilterValue] = [] {
        didSet {
            viewModel.filters = filters
            updateHostingControllers()
            saveFilters()
        }
    }
    private var sourceLanguages: [(title: String, value: String)] = [] {
        didSet {
            updateHostingControllers()
        }
    }

    private var searchTextBinding: Binding<String> {
        .init(
            get: { [weak self] in self?.searchText ?? "" },
            set: { [weak self] in
                self?.searchText = $0
                self?.searchController.searchBar.text = $0
            }
        )
    }
    private var searchCommitToggleBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.searchCommitToggle ?? false },
            set: { [weak self] in self?.searchCommitToggle = $0 }
        )
    }
    private var filtersBinding: Binding<[FilterValue]> {
        .init(
            get: { [weak self] in self?.filters ?? [] },
            set: { [weak self] in self?.filters = $0 }
        )
    }

    private var mainView: SearchContentView {
        SearchContentView(
            viewModel: viewModel,
            searchText: searchTextBinding,
            searchCommitToggle: searchCommitToggleBinding,
            filters: filtersBinding,
            openResult: open(result:),
            path: NavigationCoordinator(rootViewController: self)
        )
    }
    private var headerView: FilterHeaderView {
        FilterHeaderView(
            filters: [
                .init(
                    id: "contentRating",
                    title: NSLocalizedString("CONTENT_RATING"),
                    value: .multiselect(.init(
                        canExclude: true,
                        options: SourceContentRating.allCases.map { $0.title },
                        ids: SourceContentRating.allCases.map { $0.stringValue }
                    ))
                ),
                .init(
                    id: "languages",
                    title: NSLocalizedString("LANGUAGES"),
                    value: .multiselect(.init(
                        canExclude: true,
                        usesTagStyle: true,
                        options: sourceLanguages.map { $0.title },
                        ids: sourceLanguages.map { $0.value }
                    ))
                ),
                .init(
                    id: "sources",
                    title: NSLocalizedString("SOURCES"),
                    value: .multiselect(.init(
                        canExclude: true,
                        options: sources.map { $0.name },
                        ids: sources.map { $0.key }
                    ))
                )
            ],
            enabledFilters: filtersBinding
        )
    }

    private lazy var mainHostingController = UIHostingController(rootView: mainView)
    private lazy var headerHostingController = {
        let headerHostingController = UIHostingController(rootView: headerView)
        headerHostingController.view.backgroundColor = .clear
        headerHostingController.view.clipsToBounds = false
        headerHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return headerHostingController
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
        // fix search bar not activating on first present
        navigationItem.searchController = searchController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
        observe()
    }

    func configure() {
        title = NSLocalizedString("SEARCH")
        view.backgroundColor = .systemBackground

        if #available(iOS 16, *) {
            navigationItem.preferredSearchBarPlacement = .stacked
        }

        searchController.hidesNavigationBarDuringPresentation = true
        searchController.searchBar.delegate = self

        // add search filters to scope bar
        searchController.searchBar.showsScopeBar = true
        searchController.searchBar.scopeButtonTitles = [""]
        (searchController.searchBar.value(forKey: "_scopeBar") as? UIView)?.isHidden = true

        if
            let containerView = searchController.searchBar.value(forKey: "_scopeBarContainerView") as? UIView,
            !containerView.subviews.contains(where: { String(describing: $0.classForCoder).contains("UIHostingView") })
        {
            containerView.clipsToBounds = false
            containerView.addSubview(headerHostingController.view)

            NSLayoutConstraint.activate([
                headerHostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                headerHostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                headerHostingController.view.leadingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.leadingAnchor),
                headerHostingController.view.trailingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.trailingAnchor)
            ])
        }

        addChild(mainHostingController)
        view.addSubview(mainHostingController.view)
        mainHostingController.didMove(toParent: self)

        let filtersData = UserDefaults.standard.data(forKey: "Search.filters")
        if let filtersData {
            let enabledFilters = try? JSONDecoder().decode([FilterValue].self, from: filtersData)
            filters = enabledFilters ?? []
        }

        loadSources()
    }

    func constrain() {
        mainHostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainHostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mainHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func observe() {
        NotificationCenter.default.publisher(for: .updateSourceList)
            .sink { [weak self] _ in
                guard let self else { return }
                loadSources()
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // fixes scope bar being hidden when dismissing and re-presenting the view
        if let containerView = searchController.searchBar.value(forKey: "_scopeBarContainerView") as? UIView {
            containerView.alpha = 1
            containerView.isHidden = false
        }
    }

    private func updateHostingControllers() {
        mainHostingController.rootView = mainView
        headerHostingController.rootView = headerView
    }

    private func loadSources() {
        sources = SourceManager.shared.sources

        // ensure filters don't reference removed sources
        filters = filters.compactMap {
            switch $0 {
                case let .multiselect(id, included, excluded):
                    if id == "sources" {
                        let validSourceIds = Set(sources.map { $0.key })
                        let filteredIncluded = included.filter { validSourceIds.contains($0) }
                        let filteredExcluded = excluded.filter { validSourceIds.contains($0) }
                        if filteredIncluded.isEmpty && filteredExcluded.isEmpty {
                            return nil
                        }
                        return .multiselect(
                            id: id,
                            included: filteredIncluded,
                            excluded: filteredExcluded
                        )
                    }
                default:
                    break
            }
            return $0
        }
    }

    private func loadSourceLanguages() {
        var languages: Set<String> = []
        for source in viewModel.sources {
            languages.formUnion(source.getSelectedLanguages())
        }
        let hasMulti = languages.remove("multi") != nil
        var sortedLanguages = languages.sorted()
        if hasMulti {
            sortedLanguages.insert("multi", at: 0)
        }
        sourceLanguages = sortedLanguages.map { code in
            (
                title: {
                    if code == "multi" {
                        NSLocalizedString("MULTI_LANGUAGE")
                    } else {
                        Locale.current.localizedString(forIdentifier: code) ?? code
                    }
                }(),
                value: code
            )
        }

        // ensure filters don't reference removed languages
        filters = filters.compactMap {
            switch $0 {
                case let .multiselect(id, included, excluded):
                    if id == "languages" {
                        let validLanguages = Set(sourceLanguages.map { $0.value })
                        let filteredIncluded = included.filter { validLanguages.contains($0) }
                        let filteredExcluded = excluded.filter { validLanguages.contains($0) }
                        if filteredIncluded.isEmpty && filteredExcluded.isEmpty {
                            return nil
                        }
                        return .multiselect(
                            id: id,
                            included: filteredIncluded,
                            excluded: filteredExcluded
                        )
                    }
                default:
                    break
            }
            return $0
        }
    }

    private func saveFilters() {
        let filtersData = try? JSONEncoder().encode(filters)
        if let filtersData {
            UserDefaults.standard.setValue(filtersData, forKey: "Search.filters")
        }
    }

    private func open(result: SearchContentView.ViewModel.SearchResult) {
        if let legacySource = result.source.legacySource {
            let sourceController = SourceViewController(source: legacySource)
            sourceController.hidesListings = true
            sourceController.navigationItem.searchController?.searchBar.text = searchText
            Task {
                await sourceController.viewModel.setTitleQuery(searchText)
                await sourceController.viewModel.setCurrentPage(1)
                await sourceController.viewModel.setManga(result.result.entries.map { $0.toOld().toInfo() })
                await sourceController.viewModel.setHasMore(result.result.hasNextPage)
                navigationController?.pushViewController(sourceController, animated: true)
            }
        } else {
            let sourceController = NewSourceViewController(source: result.source, onlySearch: true, searchQuery: searchText)
            navigationController?.pushViewController(sourceController, animated: true)
        }
    }
}

// MARK: UISearchBarDelegate
extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // update search text for the search results
        self.searchText = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // trigger search commit (immediate search without delay)
        self.searchCommitToggle.toggle()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchText = ""
    }
}
