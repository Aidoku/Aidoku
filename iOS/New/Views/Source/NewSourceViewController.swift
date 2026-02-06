//
//  NewSourceViewController.swift
//  Aidoku
//
//  Created by Skitty on 8/21/23.
//

import AidokuRunner
import Combine
import NukeUI
import SafariServices
import SwiftUI

class NewSourceViewController: UIViewController {
    let source: AidokuRunner.Source
    // if the listings/home should be hidden and the search view shown by default
    private let onlySearch: Bool

    private let searchController: UISearchController = .init(searchResultsController: nil)

    private var originalNavbarAppearance: UINavigationBarAppearance?
    private var originalNavbarEdgeAppearance: UINavigationBarAppearance?

    private var cancellable: AnyCancellable?

    private lazy var searchOverlayView = {
        let scrollView = UIView()
        scrollView.backgroundColor = .systemBackground
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private lazy var searchViewController = SourceSearchViewController(source: source)

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
            importHostingController.rootView = importFileView
        }
    }
    private var searchText: String {
        didSet {
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
            searchViewController.enabledFilters = enabledFilters
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

    private var filterSheetView: FilterListSheetView {
        FilterListSheetView(
            filters: filters ?? [],
            showResetButton: true,
            enabledFilters: enabledFiltersBinding
        )
    }

    struct ImportFileView: View {
        @Binding var importing: Bool

        var body: some View {
            EmptyView()
                .sheet(isPresented: $importing) {
                    LocalFileImportView()
                }
        }
    }
    private var importFileView: ImportFileView {
        ImportFileView(importing: importingBinding)
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
    private lazy var importHostingController = UIHostingController(rootView: importFileView)

    init(
        source: AidokuRunner.Source,
        onlySearch: Bool? = nil,
        searchQuery: String? = nil
    ) {
        self.source = source
        self.onlySearch = onlySearch ?? source.onlySearch
        self.searchText = searchQuery ?? ""
        super.init(nibName: nil, bundle: nil)

        self.searchViewController.searchText = self.searchText

        // load filters from defaults
        let filtersData: Data? = SettingsStore.shared.get(key: "\(source.id).filters")
        if let filtersData {
            let enabledFilters = try? JSONDecoder().decode([FilterValue].self, from: filtersData)
            self.enabledFilters = enabledFilters ?? []
            self.searchViewController.enabledFilters = self.enabledFilters
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // if it isn't removed, an old search bar can potentially block pressing the filter
        // header buttons in a newer source view controller for some reason
        searchController.searchBar.removeFromSuperview()
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

        // fix iPadOS 26 bug
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            typealias SetClearAsCancelButtonVisibility = @convention(c) (NSObject, Selector, NSInteger) -> Void
            let selector = NSSelectorFromString("_setClearAsCancelButtonVisibilityWhenEmpty:")
            let methodIMP = searchController.method(for: selector)
            let method = unsafeBitCast(methodIMP, to: SetClearAsCancelButtonVisibility.self)
            method(searchController, selector, 1)
        }

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
        searchController.searchBar.scopeBarBackgroundImage = nil
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
            }

            // only add these views if we need them
            addChild(mainHostingController)
            view.addSubview(mainHostingController.view)
            mainHostingController.didMove(toParent: self)

            // hide search view by default (show home view instead)
            searchOverlayView.alpha = 0
            searchOverlayView.isHidden = true

            searchViewController.view.alpha = 0
            searchViewController.view.isHidden = true
        } else {
            searchViewController.onAppear()
        }

        view.addSubview(searchOverlayView)
        addChild(searchViewController)
        searchOverlayView.addSubview(searchViewController.view)
        searchViewController.didMove(toParent: self)

        if source.id == LocalSourceRunner.sourceKey {
            addChild(importHostingController)
            view.addSubview(importHostingController.view)
            importHostingController.didMove(toParent: self)
        }
    }

    private func constrain() {
        searchOverlayView.translatesAutoresizingMaskIntoConstraints = false
        searchViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            searchOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            searchOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            searchOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            searchViewController.view.topAnchor.constraint(equalTo: searchOverlayView.topAnchor),
            searchViewController.view.bottomAnchor.constraint(equalTo: searchOverlayView.bottomAnchor),
            searchViewController.view.leadingAnchor.constraint(equalTo: searchOverlayView.leadingAnchor),
            searchViewController.view.trailingAnchor.constraint(equalTo: searchOverlayView.trailingAnchor)
        ])

        if !onlySearch {
            mainHostingController.view.translatesAutoresizingMaskIntoConstraints = false

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
                mainHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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
        if !searchOverlayView.isHidden {
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
        searchViewController.scrollToTop(animated: false)

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

        searchOverlayView.isHidden = false

        searchViewController.onAppear()

        // fade in search overlay (background) and search filters, and hide navbar background
        UIView.animate(withDuration: 0.2) {
            self.searchOverlayView.alpha = 1
            self.searchFilterController.view.alpha = 1
            self.setNavigationBarOpaque(true)

            // show search bar drawer if it was hidden
            if !self.source.hasListings {
                self.navigationItem.searchController = self.searchController
                // prevent the scope bar background from appearing
                self.searchController.searchBar.scopeBarBackgroundImage = nil
            }
        } completion: { _ in
            // fade in search content
            self.searchViewController.view.isHidden = false
            UIView.animate(withDuration: 0.1) {
                self.searchViewController.view.alpha = 1
            }

            // reset scroll view shift
            if let mainScrollView = self.findScrollView(in: self.mainHostingController.view) {
                mainScrollView.transform = .identity
            }
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
            let tabBarController = window.rootViewController as? UITabBarController
        else {
            return
        }

        // pop the scroll view off the search overlay and put it on the window above everything;
        // stops the content from moving around when the navbar height changes during transition
        let originalFrame = searchViewController.view.frame

        searchViewController.removeFromParent()
        searchViewController.view.removeFromSuperview()
        searchViewController.view.translatesAutoresizingMaskIntoConstraints = true

        searchViewController.view.frame = UIScreen.main.bounds
        searchViewController.view.transform = .identity.translatedBy(x: 0, y: view.safeAreaInsets.top)

        // scroll view frame changes automatically, so make sure it doesn't clip in the wrong place
        searchViewController.view.clipsToBounds = false

        // use mask to clip scroll view so it doesn't cover tab bar
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: CGRect(
            x: 0,
            y: 0,
            width: window.bounds.width,
            // half point for tab bar separator
            height: tabBarController.tabBar.frame.origin.y - 0.5 - view.safeAreaInsets.top
        ))
        maskLayer.path = path.cgPath
        searchViewController.view.layer.mask = maskLayer

        window.addSubview(searchViewController.view)

        searchController.searchBar.showsScopeBar = false

        UIView.animate(withDuration: 0.1) {
            // fade out search content
            self.searchViewController.view.alpha = 0
        } completion: { _ in
            self.searchViewController.view.isHidden = true

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
                self.searchOverlayView.alpha = 0
                // reset navigation bar background
                self.setNavigationBarOpaque(false)
            } completion: { _ in
                self.searchOverlayView.isHidden = true

                // put scroll view back on original superview
                self.searchViewController.view.removeFromSuperview()
                self.addChild(self.searchViewController)
                self.searchOverlayView.addSubview(self.searchViewController.view)
                self.searchViewController.didMove(toParent: self)

                self.searchViewController.view.frame = originalFrame
                self.searchViewController.view.transform = .identity
                self.searchViewController.view.layer.mask = nil

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
            guard let self else { return }
            Task {
                guard
                    let url = (try? await self.source.getBaseUrl()) ?? self.source.urls.first,
                    let scheme = url.scheme,
                    scheme.hasPrefix("http")
                else {
                    let alert = UIAlertController(
                        title: NSLocalizedString("INVALID_URL"),
                        message: NSLocalizedString("INVALID_URL_TEXT"),
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel) { _ in })
                    alert.view.tintColor = self.view.tintColor // uikit bug :)
                    self.present(alert, animated: true, completion: nil)
                    return
                }
                let safariController = SFSafariViewController(url: url)
                self.present(safariController, animated: true)
            }
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
//                        self.showImportSheet()
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
}

extension NewSourceViewController {
    private func saveEnabledFilters() {
        let filtersData = try? JSONEncoder().encode(enabledFilters)
        if let filtersData {
            SettingsStore.shared.set(key: "\(source.id).filters", value: filtersData)
        }
    }

    private func showImportSheet() {
        let viewController = UIHostingController(rootView: LocalFileImportView())
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }
}

// MARK: UISearchBarDelegate
extension NewSourceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchViewController.searchBar(searchBar, textDidChange: searchText)
        self.searchText = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchViewController.searchBarSearchButtonClicked(searchBar)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchViewController.searchBarCancelButtonClicked(searchBar)
        searchText = ""
        // dismiss search view
        if !onlySearch {
            hideSearchView()
        }
    }
}
