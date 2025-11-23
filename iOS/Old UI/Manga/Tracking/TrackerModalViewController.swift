//
//  TrackerModalViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/26/22.
//

import AidokuRunner
import UIKit

class TrackerModalViewController: MiniModalViewController {
    let manga: AidokuRunner.Manga
    var swiftuiViewController: HostingController<TrackerListView>

    init(manga: AidokuRunner.Manga) {
        self.manga = manga
        swiftuiViewController = HostingController(rootView: TrackerListView(manga: manga))
        swiftuiViewController.view.backgroundColor = .clear
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        containerView.clipsToBounds = true

        addChild(swiftuiViewController)
        scrollView.addSubview(swiftuiViewController.view)
        swiftuiViewController.didMove(toParent: self)

        swiftuiViewController.view.translatesAutoresizingMaskIntoConstraints = false

        let screenHeightConstraint = scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: UIScreen.main.bounds.height - 64)
        screenHeightConstraint.priority = .defaultHigh

        let hostingHeightConstraint = scrollView.heightAnchor.constraint(equalTo: swiftuiViewController.view.heightAnchor, constant: 20)
        hostingHeightConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            swiftuiViewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            swiftuiViewController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            swiftuiViewController.view.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            screenHeightConstraint,
            hostingHeightConstraint
        ])
    }
}
