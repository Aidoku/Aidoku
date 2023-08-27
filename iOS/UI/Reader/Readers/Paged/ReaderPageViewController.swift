//
//  ReaderPageViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class ReaderPageViewController: BaseViewController {

    enum InfoPageType {
        case previous
        case next
    }

    enum PageType {
        case info(InfoPageType)
        case page
    }

    let type: PageType

    private var infoView: ReaderInfoPageView?
    private var zoomView: ZoomableScrollView?
    var pageView: ReaderPageView?
    lazy var reloadButton = UIButton(type: .roundedRect)

    var currentChapter: Chapter? {
        get { infoView?.currentChapter }
        set { infoView?.currentChapter = newValue }
    }
    var previousChapter: Chapter? {
        get { infoView?.previousChapter }
        set { infoView?.previousChapter = newValue }
    }
    var nextChapter: Chapter? {
        get { infoView?.nextChapter }
        set { infoView?.nextChapter = newValue }
    }

    private var pageSet = false
    private var page: Page?

    init(type: PageType) {
        self.type = type
        super.init()

        // need this so the page / chapters can be set before the rest of the views are loaded
        switch type {
        case .info(let infoPageType):
            infoView = ReaderInfoPageView(type: infoPageType == .previous ? .previous : .next)
        case .page:
            pageView = ReaderPageView()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        switch type {
        case .info:
            // info view
            guard let infoView = infoView else { return }
            infoView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(infoView)

        case .page:
            // zoom view
            let zoomView = ZoomableScrollView(frame: view.bounds)
            zoomView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(zoomView)

            // page view
            guard let pageView = pageView else { return }
            pageView.translatesAutoresizingMaskIntoConstraints = false
            zoomView.addSubview(pageView)
            zoomView.zoomView = pageView

            reloadButton.isHidden = true
            reloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
            reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
            reloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
            reloadButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(reloadButton)

            self.zoomView = zoomView
            self.pageView = pageView
            self.reloadButton = reloadButton
        }
    }

    override func constrain() {
        if let infoView = infoView {
            NSLayoutConstraint.activate([
                infoView.topAnchor.constraint(equalTo: view.topAnchor),
                infoView.leftAnchor.constraint(equalTo: view.leftAnchor),
                infoView.rightAnchor.constraint(equalTo: view.rightAnchor),
                infoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else if let zoomView = zoomView, let pageView = pageView {
            NSLayoutConstraint.activate([
                zoomView.topAnchor.constraint(equalTo: view.topAnchor),
                zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
                zoomView.rightAnchor.constraint(equalTo: view.rightAnchor),
                zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                pageView.widthAnchor.constraint(equalTo: zoomView.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.heightAnchor),
                pageView.centerXAnchor.constraint(equalTo: zoomView.centerXAnchor),
                pageView.centerYAnchor.constraint(equalTo: zoomView.centerYAnchor),

                reloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    func setPage(_ page: Page, sourceId: String? = nil) {
        guard !pageSet, let pageView = pageView else { return }
        pageSet = true
        self.page = page
        zoomView?.zoomEnabled = false
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId)
            zoomView?.zoomEnabled = result
            if !result {
                pageSet = false
                pageView.progressView.isHidden = true
                reloadButton.isHidden = false
            } else {
                reloadButton.isHidden = true
            }
        }
    }

    @objc func reload() {
        reloadButton.isHidden = true
        pageView?.progressView.setProgress(value: 0, withAnimation: false)
        pageView?.progressView.isHidden = false
        if let page = page {
            setPage(page)
        }
    }
}
