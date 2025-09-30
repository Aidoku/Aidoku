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
        swiftuiViewController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(swiftuiViewController.view)
        swiftuiViewController.didMove(toParent: self)

        swiftuiViewController.view.topAnchor.constraint(equalTo: scrollView.topAnchor).isActive = true
        swiftuiViewController.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
        swiftuiViewController.view.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor).isActive = true

        scrollView.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true

        let screenHeightConstraint = scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: UIScreen.main.bounds.height - 64)
        screenHeightConstraint.priority = .defaultHigh
        screenHeightConstraint.isActive = true

        let hostingHeightConstraint = scrollView.heightAnchor.constraint(equalTo: swiftuiViewController.view.heightAnchor, constant: 20)
        hostingHeightConstraint.priority = .defaultLow
        hostingHeightConstraint.isActive = true

        scrollView.widthAnchor.constraint(equalTo: containerView.widthAnchor).isActive = true
    }
}
