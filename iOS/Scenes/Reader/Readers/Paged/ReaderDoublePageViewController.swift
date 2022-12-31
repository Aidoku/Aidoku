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

    init(firstPage: ReaderPageViewController, secondPage: ReaderPageViewController, direction: Direction) {
        self.firstPageController = firstPage
        self.secondPageController = secondPage
        self.direction = direction
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomView)

        pageStack.axis = .horizontal
        pageStack.distribution = .fillProportionally
        pageStack.alignment = .center
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        zoomView.addSubview(pageStack)
        zoomView.zoomView = pageStack

        guard
            let firstPageView = firstPageController.pageView,
            let secondPageView = secondPageController.pageView
        else {
            return
        }

        firstPageView.translatesAutoresizingMaskIntoConstraints = false

        if direction == .ltr {
            pageStack.addArrangedSubview(firstPageView)
        }

        secondPageView.translatesAutoresizingMaskIntoConstraints = false
        pageStack.addArrangedSubview(secondPageView)

        if direction == .rtl {
            pageStack.addArrangedSubview(firstPageView)
        }

        firstReloadButton.isHidden = true
        firstReloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        firstReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        firstReloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        firstReloadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(firstReloadButton)

        secondReloadButton.isHidden = true
        secondReloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        secondReloadButton.addTarget(self, action: #selector(reload(_:)), for: .touchUpInside)
        secondReloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
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

        NSLayoutConstraint.activate([
            firstPageView.widthAnchor.constraint(equalTo: firstPageView.imageView.widthAnchor),
            firstPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),
            secondPageView.widthAnchor.constraint(equalTo: secondPageView.imageView.widthAnchor),
            secondPageView.heightAnchor.constraint(equalTo: pageStack.heightAnchor),

            firstReloadButton.centerXAnchor.constraint(equalTo: firstPageView.centerXAnchor),
            firstReloadButton.centerYAnchor.constraint(equalTo: firstPageView.centerYAnchor),

            secondReloadButton.centerXAnchor.constraint(equalTo: secondPageView.centerXAnchor),
            secondReloadButton.centerYAnchor.constraint(equalTo: secondPageView.centerYAnchor)
        ])
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
