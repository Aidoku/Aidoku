//
//  SourceListingViewController.swift
//  Aidoku
//
//  Created by Skitty on 12/27/24.
//

import SwiftUI
import AidokuRunner

class SourceListingViewController: UIViewController {
    let source: AidokuRunner.Source
    let listing: AidokuRunner.Listing

    init(source: AidokuRunner.Source, listing: AidokuRunner.Listing) {
        self.source = source
        self.listing = listing

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = listing.name
        navigationItem.largeTitleDisplayMode = .never

        let path = NavigationCoordinator(rootViewController: self)
        let rootView = SourceListingView(source: source, listing: listing)
            .environmentObject(path)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        view.addSubview(hostingController.view)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private struct SourceListingView: View {
    let source: AidokuRunner.Source
    let listing: AidokuRunner.Listing

    var body: some View {
        MangaListView(source: source, title: listing.name, listingKind: listing.kind) { page in
            try await source.getMangaList(listing: listing, page: page)
        }
    }
}
