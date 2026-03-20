//
//  ReaderDoublePageViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/19/22.
//

import UIKit

class ReaderDoublePageViewController: BaseViewController {

    enum Direction {
        case rtl
        case ltr
    }

    lazy var zoomView = ZoomableScrollView(frame: view.bounds)
    private let pageStack = UIStackView()
    let firstPageController: ReaderPageViewController
    let secondPageController: ReaderPageViewController

    private lazy var firstReloadButton = UIButton(type: .roundedRect)
    private lazy var secondReloadButton = UIButton(type: .roundedRect)

    var direction: Direction {
        didSet {
            if direction != oldValue {
                pageStack.addArrangedSubview(pageStack.subviews[0])
            }
        }
    }

    private var firstPageSet = false
    private var secondPageSet = false
    private var firstPage: Page?
    private var secondPage: Page?
    private var pageLayoutConstraints: [NSLayoutConstraint] = []

    init(firstPage: ReaderPageViewController, secondPage: ReaderPageViewController, direction: Direction) {
        self.firstPageController = firstPage
        self.secondPageController = secondPage
        self.direction = direction
        super.init()
        self.firstPageController.isInDoublePageController = true
        self.secondPageController.isInDoublePageController = true
    }

    override func configure() {
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomView)

        pageStack.axis = .horizontal
        pageStack.distribution = .fillEqually
        pageStack.alignment = .center
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        zoomView.addSubview(pageStack)
        zoomView.zoomView = pageStack

        firstReloadButton.isHidden = true
        firstReloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        firstReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        firstReloadButton.configuration = .borderless()
        firstReloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        firstReloadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(firstReloadButton)

        secondReloadButton.isHidden = true
        secondReloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        secondReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        secondReloadButton.configuration = .borderless()
        secondReloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        secondReloadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(secondReloadButton)
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
            zoomView.rightAnchor.constraint(equalTo: view.rightAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pageStack.widthAnchor.constraint(lessThanOrEqualTo: zoomView.widthAnchor),
            pageStack.heightAnchor.constraint(equalTo: zoomView.heightAnchor),
            pageStack.centerXAnchor.constraint(equalTo: zoomView.centerXAnchor),
            pageStack.centerYAnchor.constraint(equalTo: zoomView.centerYAnchor)
        ])

        guard
            let firstPageView = firstPageController.pageView,
            let secondPageView = secondPageController.pageView
        else {
            return
        }

        pageLayoutConstraints = [
            firstPageView.widthAnchor.constraint(equalTo: firstPageView.imageView.widthAnchor),
            firstPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),
            secondPageView.widthAnchor.constraint(equalTo: secondPageView.imageView.widthAnchor),
            secondPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),

            firstReloadButton.centerXAnchor.constraint(equalTo: firstPageView.centerXAnchor),
            firstReloadButton.centerYAnchor.constraint(equalTo: firstPageView.centerYAnchor),

            secondReloadButton.centerXAnchor.constraint(equalTo: secondPageView.centerXAnchor),
            secondReloadButton.centerYAnchor.constraint(equalTo: secondPageView.centerYAnchor)
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard
            let firstPageView = firstPageController.pageView,
            let secondPageView = secondPageController.pageView
        else { return }

        firstPageController.zoomView?.setZoomScale(1, animated: false)
        secondPageController.zoomView?.setZoomScale(1, animated: false)

        if
            !firstPageView.isDescendant(of: pageStack)
                || !secondPageView.isDescendant(of: pageStack)
        {
            for view in pageStack.arrangedSubviews {
                pageStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            for controller in [firstPageController, secondPageController] {
                NSLayoutConstraint.deactivate(controller.doublePageRestorationConstraints)
                controller.doublePageRestorationConstraints = []
                if let pageView = controller.pageView, pageView.superview !== pageStack {
                    pageView.removeFromSuperview()
                }
                controller.isInDoublePageController = true
            }

            let orderedViews = direction == .ltr
                ? [firstPageView, secondPageView]
                : [secondPageView, firstPageView]
            for view in orderedViews {
                pageStack.addArrangedSubview(view)
            }
        }
        NSLayoutConstraint.activate(pageLayoutConstraints)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NSLayoutConstraint.deactivate(pageLayoutConstraints)
        for controller in [firstPageController, secondPageController] {
            guard
                let pageView = controller.pageView,
                let zoomView = controller.zoomView,
                pageView.isDescendant(of: pageStack)
            else { continue }
            controller.isInDoublePageController = false
            pageStack.removeArrangedSubview(pageView)
            pageView.removeFromSuperview()
            zoomView.addSubview(pageView)
            pageView.translatesAutoresizingMaskIntoConstraints = false
            let constraints = [
                pageView.widthAnchor.constraint(equalTo: zoomView.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.heightAnchor)
            ]
            NSLayoutConstraint.activate(constraints)
            controller.doublePageRestorationConstraints = constraints
        }
    }

    // TODO: fix `SWIFT TASK CONTINUATION MISUSE: setPageImage(url:sourceId:) leaked its continuation!`
    func setPage(_ page: Page, sourceId: String? = nil, for pos: ReaderPagedViewController.PagePosition) {
        let pageView: ReaderPageView?
        let reloadButton: UIButton
        switch pos {
            case .first:
                firstPageSet = true
                firstPage = page
                pageView = firstPageController.pageView
                reloadButton = firstReloadButton
            case .second:
                secondPageSet = true
                secondPage = page
                pageView = secondPageController.pageView
                reloadButton = secondReloadButton
        }
        guard let pageView = pageView else {
            return
        }
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId)
            if !result {
                if pos == .first {
                    firstPageSet = false
                } else {
                    secondPageSet = false
                }
                reloadButton.isHidden = false
            } else {
                reloadButton.isHidden = true
            }
        }
    }

    @objc func reload(_ sender: UIButton) {
        if sender == firstReloadButton {
            guard let firstPageView = firstPageController.pageView else { return }
            firstReloadButton.isHidden = true
            firstPageView.progressView.setProgress(value: 0, withAnimation: false)
            firstPageView.progressView.isHidden = false
            if let firstPage = firstPage {
                setPage(firstPage, for: .first)
            }
        } else {
            guard let secondPageView = secondPageController.pageView else { return }
            secondReloadButton.isHidden = true
            secondPageView.progressView.setProgress(value: 0, withAnimation: false)
            secondPageView.progressView.isHidden = false
            if let secondPage = secondPage {
                setPage(secondPage, for: .second)
            }
        }
    }
}
