//
//  NewSourceViewController.swift
//  Aidoku
//
//  Created by Skitty on 8/21/23.
//

import SwiftUI
import AidokuRunner
import NukeUI
import SafariServices

class NewSourceViewController: UIViewController {
    let source: AidokuRunner.Source
    // if the listings/home should be hidden and the search view shown by default
    private let onlySearch: Bool

    private let searchController: UISearchController = .init(searchResultsController: nil)

    private var originalNavbarAppearance: UINavigationBarAppearance?
    private var originalNavbarEdgeAppearance: UINavigationBarAppearance?

    private lazy var searchOverlay = UIView()

    // MARK: SwiftUI Bindings
    private var listings: [AidokuRunner.Listing] = [] {
        didSet {
            updateHostingControllers()
        }
    }
    private var headerListingSelection: Int = 0 {
        didSet {
            updateHostingControllers()
        }
    }
    private var importing: Bool = false {
        didSet {
            updateHostingControllers()
        }
    }
    private var searchText: String {
        didSet {
            updateHostingControllers()
            handleFilterHeaderVisibility()
        }
    }
    private var filters: [AidokuRunner.Filter]? {
        didSet {
            updateHostingControllers()
        }
    }
    private var enabledFilters: [FilterValue] = [] {
        didSet {
            updateHostingControllers()
            saveEnabledFilters()
        }
    }
    private var filtersEmpty: Bool = false {
        didSet {
            if onlySearch && filtersEmpty {
                searchController.searchBar.showsScopeBar = false
            }
        }
    }
    private var searchHidden: Bool = true {
        didSet {
            updateHostingControllers()
        }
    }
    private var searchCommitToggle: Bool = false {
        didSet {
            updateHostingControllers()
        }
    }
    private var searchScrollTopToggle: Bool = false {
        didSet {
            updateHostingControllers()
        }
    }

    private var listingsBinding: Binding<[AidokuRunner.Listing]> {
        .init(
            get: { [weak self] in self?.listings ?? [] },
            set: { [weak self] in self?.listings = $0 }
        )
    }
    private var headerListingSelectionBinding: Binding<Int> {
        .init(
            get: { [weak self] in self?.headerListingSelection ?? 0 },
            set: { [weak self] in self?.headerListingSelection = $0 }
        )
    }
    private var importingBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.importing ?? false },
            set: { [weak self] in self?.importing = $0 }
        )
    }
    private var searchTextBinding: Binding<String> {
        .init(
            get: { [weak self] in self?.searchText ?? "" },
            set: { [weak self] in self?.searchText = $0 }
        )
    }
    private var filtersBinding: Binding<[AidokuRunner.Filter]?> {
        .init(
            get: { [weak self] in self?.filters },
            set: { [weak self] in self?.filters = $0 }
        )
    }
    private var enabledFiltersBinding: Binding<[FilterValue]> {
        .init(
            get: { [weak self] in self?.enabledFilters ?? [] },
            set: { [weak self] in self?.enabledFilters = $0 }
        )
    }
    private var filtersEmptyBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.filtersEmpty ?? false },
            set: { [weak self] in self?.filtersEmpty = $0 }
        )
    }
    private var searchHiddenBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.searchHidden ?? true },
            set: { [weak self] in self?.searchHidden = $0 }
        )
    }
    private var searchCommitToggleBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.searchCommitToggle ?? false },
            set: { [weak self] in self?.searchCommitToggle = $0 }
        )
    }
    private var searchScrollTopToggleBinding: Binding<Bool> {
        .init(
            get: { [weak self] in self?.searchScrollTopToggle ?? false },
            set: { [weak self] in self?.searchScrollTopToggle = $0 }
        )
    }

    // MARK: SwiftUI Views
    private var searchFilterHeaderView: SearchFilterHeaderView {
        SearchFilterHeaderView(
            source: source,
            filters: filtersBinding,
            enabledFilters: enabledFiltersBinding,
            filtersEmpty: filtersEmptyBinding
        ) { [weak self] in
            guard let self else { return }
            self.present(
                UIHostingController(rootView: self.filterSheetView),
                animated: true
            )
        }
    }

    private var listingsHeaderView: ListingsHeaderView {
        ListingsHeaderView(
            source: source,
            listings: listingsBinding,
            selectedListing: headerListingSelectionBinding
        )
    }

    private var mainView: SourceHomeContentView {
        SourceHomeContentView(
            source: source,
            holdingViewController: self,
            listings: listingsBinding,
            headerListingSelection: headerListingSelectionBinding
        )
    }

    private var searchOverlayView: SourceSearchView {
        SourceSearchView(
            source: source,
            holdingViewController: self,
            searchText: searchTextBinding,
            enabledFilters: enabledFiltersBinding,
            hidden: searchHiddenBinding,
            searchCommitToggle: searchCommitToggleBinding,
            scrollTopToggle: searchScrollTopToggleBinding,
            importing: importingBinding
        )
    }

    private var filterSheetView: FilterListSheetView {
        FilterListSheetView(
            filters: filters ?? [],
            showResetButton: true,
            enabledFilters: enabledFiltersBinding
        )
    }

    // MARK: Hosting Controllers
    private lazy var searchFilterController = {
        let searchFilterController = UIHostingController(rootView: searchFilterHeaderView)
        if !onlySearch {
            searchFilterController.view.alpha = 0
        }
        searchFilterController.view.backgroundColor = .clear
        searchFilterController.view.clipsToBounds = false
        searchFilterController.view.translatesAutoresizingMaskIntoConstraints = false
        return searchFilterController
    }()
    private lazy var listingHeaderController = UIHostingController(rootView: listingsHeaderView)
    private lazy var mainHostingController = UIHostingController(rootView: mainView)
    private lazy var searchOverlayController = UIHostingController(rootView: searchOverlayView)

    init(
        source: AidokuRunner.Source,
        onlySearch: Bool? = nil,
        searchQuery: String? = nil
    ) {
        self.source = source
        self.onlySearch = onlySearch ?? source.onlySearch
        self.searchText = searchQuery ?? ""
        super.init(nibName: nil, bundle: nil)

        // load filters from defaults
        let filtersData: Data? = SettingsStore.shared.get(key: "\(source.id).filters")
        if let filtersData {
            let enabledFilters = try? JSONDecoder().decode([FilterValue].self, from: filtersData)
            self.enabledFilters = enabledFilters ?? []
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
    }

    func configure() {
        title = source.name
        view.backgroundColor = .systemBackground

        loadNavbarButtons()

        navigationController?.delegate = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        if #available(iOS 16, *) {
            navigationItem.preferredSearchBarPlacement = .stacked
        }

        searchController.hidesNavigationBarDuringPresentation = true
        searchController.searchBar.delegate = self

        setSearchBarHidden(!onlySearch)

        // disable the search bar tap gesture while it's hidden
        let searchBar = searchController.searchBar
        if !onlySearch {
            searchBar.gestureRecognizers?.forEach {
                $0.isEnabled = false
            }
        }

        searchBar.text = searchText

        // add search filters to scope bar
        searchController.searchBar.showsScopeBar = onlySearch
        searchController.searchBar.scopeButtonTitles = [""]
        (searchController.searchBar.value(forKey: "_scopeBar") as? UIView)?.isHidden = true

        if
            let containerView = searchController.searchBar.value(forKey: "_scopeBarContainerView") as? UIView,
            !containerView.subviews.contains(where: { String(describing: $0.classForCoder).contains("UIHostingView") })
        {
            containerView.clipsToBounds = false
            containerView.addSubview(searchFilterController.view)

            NSLayoutConstraint.activate([
                searchFilterController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                searchFilterController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                searchFilterController.view.leadingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.leadingAnchor),
                searchFilterController.view.trailingAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.trailingAnchor)
            ])
        }

        // replace search bar view with listings header view
        if !onlySearch {
            if source.hasListings {
                listingHeaderController.view.backgroundColor = .clear
                listingHeaderController.view.clipsToBounds = false
                searchBar.addSubview(listingHeaderController.view)

                // this superview keeps setting clipsToBounds to true, which messes up the shadow on ios 26
                listingHeaderController.view.superview?.forceNoClip()
            } else {
                navigationItem.searchController = nil
//                searchController.isActive = false
            }
        }

        searchOverlayController.view.backgroundColor = .systemBackground
        searchOverlayController.view.clipsToBounds = false
        addChild(searchOverlayController)
        searchOverlayController.didMove(toParent: self)

        if onlySearch {
            searchHidden = false
            view.addSubview(searchOverlayController.view)
        } else {
            // only add these views if we need them
            addChild(mainHostingController)
            view.addSubview(mainHostingController.view)
            mainHostingController.didMove(toParent: self)

            searchOverlay.isHidden = true
            searchOverlay.layer.opacity = 0
            searchOverlay.backgroundColor = .systemBackground
            searchOverlay.clipsToBounds = false
            view.addSubview(searchOverlay)

            searchOverlayController.view.alpha = 0
            searchOverlayController.view.isHidden = true
            searchOverlay.addSubview(searchOverlayController.view)
        }
    }

    private func constrain() {
        searchOverlayController.view.translatesAutoresizingMaskIntoConstraints = false

        if onlySearch {
            NSLayoutConstraint.activate([
                searchOverlayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchOverlayController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                searchOverlayController.view.topAnchor.constraint(equalTo: view.topAnchor),
                searchOverlayController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else {
            mainHostingController.view.translatesAutoresizingMaskIntoConstraints = false
            searchOverlay.translatesAutoresizingMaskIntoConstraints = false

            if source.hasListings {
                let searchBar = searchController.searchBar
                listingHeaderController.view.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    listingHeaderController.view.topAnchor.constraint(equalTo: searchBar.topAnchor),
                    listingHeaderController.view.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
                    listingHeaderController.view.leadingAnchor.constraint(equalTo: searchBar.safeAreaLayoutGuide.leadingAnchor),
                    listingHeaderController.view.trailingAnchor.constraint(equalTo: searchBar.safeAreaLayoutGuide.trailingAnchor)
                ])
            }

            NSLayoutConstraint.activate([
                mainHostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                mainHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                mainHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mainHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                searchOverlay.topAnchor.constraint(equalTo: view.topAnchor),
                searchOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                searchOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                searchOverlayController.view.topAnchor.constraint(equalTo: searchOverlay.topAnchor),
                searchOverlayController.view.bottomAnchor.constraint(equalTo: searchOverlay.bottomAnchor),
                searchOverlayController.view.leadingAnchor.constraint(equalTo: searchOverlay.leadingAnchor),
                searchOverlayController.view.trailingAnchor.constraint(equalTo: searchOverlay.trailingAnchor)
            ])
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // save original navbar appearance
        if originalNavbarAppearance == nil, let navigationBar = navigationController?.navigationBar {
            originalNavbarAppearance = navigationBar.standardAppearance
            originalNavbarEdgeAppearance = navigationBar.scrollEdgeAppearance
        }
        if !searchOverlay.isHidden {
            // set navbar back to opaque if we entered the view while still searching
            // e.g. returned to search page after exiting manga page
            self.setNavigationBarOpaque(true)
        }
    }
}

extension NewSourceViewController: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // ensure navbar is set back to normal when view is exited
        if viewController !== self {
            if let navigationBar = navigationController.navigationBar as UINavigationBar? {
                if let originalNavbarAppearance {
                    navigationBar.standardAppearance = originalNavbarAppearance
                }
                navigationBar.scrollEdgeAppearance = originalNavbarEdgeAppearance
            }
        }
    }
}

extension NewSourceViewController {
    // show search view, hide listings view
    func showSearchView() {
        // set search view offset to top before we show it
        searchScrollTopToggle.toggle()

        // show original search bar
        setSearchBarHidden(false)

        // hide listing selector
        listingHeaderController.view.isHidden = true

        // show scope bar (for filters header)
        // shifts main scroll view down slightly to improve animation
        if !filtersEmpty, let scrollView = findScrollView(in: mainHostingController.view) {
            let searchBar = searchController.searchBar
            let previousHeight = searchBar.frame.height
            searchBar.showsScopeBar = true
            let newHeight = searchBar.frame.height
            let heightDifference = abs(previousHeight - newHeight)

            let translationTransform = CGAffineTransform.identity.translatedBy(x: 0, y: -heightDifference)
            scrollView.transform = translationTransform
        }

        searchOverlay.isHidden = false

        // fade in search overlay (background) and search filters, and hide navbar background
        UIView.animate(withDuration: 0.2) {
            self.searchOverlay.alpha = 1
            self.searchFilterController.view.alpha = 1
            self.setNavigationBarOpaque(true)

            // show search bar drawer if it was hidden
            if !self.source.hasListings {
                self.navigationItem.searchController = self.searchController
            }
        } completion: { _ in
            // fade in search content
            self.searchOverlayController.view.isHidden = false
            if self.searchHidden {
                self.searchHidden = false
            }
            UIView.animate(withDuration: 0.1) {
                self.searchOverlayController.view.alpha = 1
            }

            // reset scroll view shift
            if let mainScrollView = self.findScrollView(in: self.mainHostingController.view) {
                mainScrollView.transform = .identity
            }

            self.searchOverlayController.view.setNeedsUpdateConstraints()
        }

        // focus search bar
        Task { @MainActor in
            searchController.isActive = true
            searchController.searchBar.becomeFirstResponder()
        }
    }

    // hide search view, show listings view
    func hideSearchView() {
        guard
            let window = view.window,
            let tabBarController = window.rootViewController as? UITabBarController,
            let scrollView = findScrollView(in: searchOverlayController.view)
        else {
            return
        }

        // pop the scroll view off the search overlay and put it on the window above everything;
        // stops the content from moving around when the navbar height changes during transition
        let originalFrame = scrollView.frame
//        let newBounds = scrollView.convert(scrollView.bounds, to: window)
        let newOrigin = CGPoint(x: 0, y: view.safeAreaInsets.top)

        searchOverlayController.removeFromParent()
        searchOverlayController.view.removeFromSuperview()
        searchOverlayController.view.translatesAutoresizingMaskIntoConstraints = true
        searchOverlayController.view.frame = UIScreen.main.bounds

        scrollView.frame.origin = newOrigin
        // scroll view frame changes automatically, so make sure it doesn't clip in the wrong place
        scrollView.clipsToBounds = false

        // use mask to clip scroll view so it doesn't cover tab bar
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: CGRect(
            x: 0,
            y: view.safeAreaInsets.top,
            width: window.bounds.width,
            // half point for tab bar separator
            height: tabBarController.tabBar.frame.origin.y - 0.5 - view.safeAreaInsets.top
        ))
        maskLayer.path = path.cgPath
        searchOverlayController.view.layer.mask = maskLayer

        window.addSubview(searchOverlayController.view)

        searchController.searchBar.showsScopeBar = false

        UIView.animate(withDuration: 0.1) {
            // fade out search content
            self.searchOverlayController.view.alpha = 0
        } completion: { _ in
            self.searchOverlayController.view.isHidden = true

            // hide search bar drawer if it should be
            if !self.source.hasListings {
                self.navigationItem.searchController = nil
            }

            // hide original search bar
            self.setSearchBarHidden(true)

            // show listings header
            self.listingHeaderController.view.isHidden = false

            // hide search filters
            self.searchFilterController.view.alpha = 0

            // fix for ios 15 navbar background not updating size properly
            if UIDevice.current.systemVersion.hasPrefix("15.") {
                if
                    let navigationBar = self.navigationController?.navigationBar,
                    let backgroundView = navigationBar.value(forKey: "_backgroundView") as? UIView
                {
                    let newFrame = CGRect(
                        x: backgroundView.frame.origin.x,
                        y: backgroundView.frame.origin.y,
                        width: navigationBar.bounds.width,
                        height: navigationBar.bounds.height - backgroundView.frame.origin.y
                    )
                    (navigationBar.value(forKey: "_backgroundView") as? UIView)?.frame = newFrame
                }
            }

            UIView.animate(withDuration: 0.2) {
                // fade out search background
                self.searchOverlay.alpha = 0
                // reset navigation bar background
                self.setNavigationBarOpaque(false)
            } completion: { _ in
                self.searchOverlay.isHidden = true

                self.searchHidden = true

                // put scroll view back on original superview
                self.searchOverlayController.view.removeFromSuperview()
                self.addChild(self.searchOverlayController)
                if !self.onlySearch {
                    self.searchOverlay.addSubview(self.searchOverlayController.view)
                } else {
                    self.view.addSubview(self.searchOverlayController.view)
                }
                self.searchOverlayController.didMove(toParent: self)
//                self.searchOverlayController.view.translatesAutoresizingMaskIntoConstraints = false
//                self.searchOverlayController.view.setNeedsUpdateConstraints()

                scrollView.frame = originalFrame
                self.searchOverlayController.view.layer.mask = nil

                self.constrain()

                // show shadow line
                if let originalNavbarAppearance = self.originalNavbarAppearance {
                    self.navigationController?.navigationBar.standardAppearance = originalNavbarAppearance
                }
            }
        }
    }

    @objc private func search() {
        showSearchView()
    }

    // refresh views in hosting controllers to update bindings
    // (basically a substitute for swiftui state reactivity)
    private func updateHostingControllers() {
        searchFilterController.rootView = searchFilterHeaderView
        listingHeaderController.rootView = listingsHeaderView
        mainHostingController.rootView = mainView
        searchOverlayController.rootView = searchOverlayView
    }

    // load navbar buttons (search, website, settings)
    // - hide search button when source is onlySearch
    // - hide website button when source doesn't have a url
    // - put website and settings buttons into a menu button if we have all three
    private func loadNavbarButtons() {
        let settingsAction = UIAction(title: NSLocalizedString("SETTINGS"), image: UIImage(systemName: "gear")) { [weak self] _ in
            guard let self else { return }

            // there's a bug where navigationlinks in settingview don't work in NavigationView/NavigationStack,
            // so we need to use a uikit navigation controller instead

            let hostingController = UIHostingController(
                rootView: SourceSettingsView(source: self.source)
                    .environmentObject(NavigationCoordinator(rootViewController: self))
            )
            let navigationController = UINavigationController(rootViewController: hostingController)
            navigationController.navigationBar.prefersLargeTitles = true

            // update navigation coordinator
            hostingController.rootView = SourceSettingsView(source: self.source)
                .environmentObject(NavigationCoordinator(rootViewController: hostingController))

            present(navigationController, animated: true)
        }

        let safariAction = UIAction(title: NSLocalizedString("OPEN_WEBSITE"), image: UIImage(systemName: "safari")) { [weak self] _ in
            guard
                let self,
                let url = self.source.urls.first,
                let scheme = url.scheme,
                scheme.hasPrefix("http")
            else {
                let alert = UIAlertController(
                    title: NSLocalizedString("INVALID_URL"),
                    message: NSLocalizedString("INVALID_URL_TEXT"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
                alert.view.tintColor = self?.view.tintColor // uikit bug :)
                self?.present(alert, animated: true, completion: nil)
                return
            }
            let safariController = SFSafariViewController(url: url)
            self.present(safariController, animated: true)
        }

        let rightmostButton = if !onlySearch && source.urls.first != nil {
            UIBarButtonItem(
                title: NSLocalizedString("MORE_BARBUTTON"),
                image: UIImage(systemName: "ellipsis"),
                primaryAction: nil,
                menu: UIMenu(children: [
                    settingsAction,
                    safariAction
                ])
            )
        } else {
            UIBarButtonItem(
                title: NSLocalizedString("SETTINGS"),
                image: UIImage(systemName: "gear"),
                primaryAction: settingsAction
            )
        }

        var rightBarButtonItems: [UIBarButtonItem] = [rightmostButton]

        if !onlySearch {
            rightBarButtonItems.append(UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(search)))
        } else if source.urls.first != nil {
            rightBarButtonItems.append(
                UIBarButtonItem(
                    title: NSLocalizedString("OPEN_WEBSITE"),
                    image: UIImage(systemName: "safari"),
                    primaryAction: safariAction
                )
            )
        }

        if source.id == LocalSourceRunner.sourceKey {
            rightBarButtonItems.append(
                UIBarButtonItem(
                    title: NSLocalizedString("UPLOAD_FILE"),
                    image: UIImage(systemName: "plus"),
                    primaryAction: UIAction(title: NSLocalizedString("UPLOAD_FILE"), image: UIImage(systemName: "plus")) { [weak self] _ in
                        guard let self else { return }
                        self.importing = true
                    }
                )
            )
        }

        navigationItem.rightBarButtonItems = rightBarButtonItems
    }

    // find a uiscrollview in a view hierarchy
    // useful for finding swiftui scrollviews in a hosting controller
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    // hides the search bar so that a blank space is left on the navbar
    private func setSearchBarHidden(_ hidden: Bool) {
        self.searchController.searchBar.subviews.first?.subviews.forEach {
            $0.isHidden = hidden
        }
    }

    // toggles the navigation bar background to opaque or transparent
    private func setNavigationBarOpaque(_ opaque: Bool) {
        if #available(iOS 26.0, *) {
            // navigation bar should remain clear on ios 26
            return
        }

        guard
            !onlySearch,
            let navigationBar = navigationController?.navigationBar
        else { return }

        if opaque {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
            appearance.shadowColor = .clear

            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        } else {
            if let originalNavbarAppearance {
                navigationBar.standardAppearance = originalNavbarAppearance
                // bug fix: there's a second separator view that appears when animating
                // here, we hide it, then when the animation resets in hideSearchView, we fully restore the appearance
                navigationBar.standardAppearance.shadowColor = .clear
            }
            navigationBar.scrollEdgeAppearance = originalNavbarEdgeAppearance
        }
    }

    private func handleFilterHeaderVisibility() {
        guard source.config?.hidesFiltersWhileSearching ?? false else { return }
        if searchText.isEmpty {
            UIView.animate(withDuration: 0.2) {
                self.searchController.searchBar.showsScopeBar = true
            }
        } else {
            self.searchController.searchBar.showsScopeBar = false
        }
    }

    private func saveEnabledFilters() {
        let filtersData = try? JSONEncoder().encode(enabledFilters)
        if let filtersData {
            SettingsStore.shared.set(key: "\(source.id).filters", value: filtersData)
        }
    }
}

// MARK: UISearchBarDelegate
extension NewSourceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // update search text for the search results
        self.searchText = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        self.searchCommitToggle.toggle()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchText = ""
        // dismiss search view
        if !onlySearch {
            hideSearchView()
        }
    }
}
