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
    private var pageView: ReaderPageView2?

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

    var pageSet = false

    init(type: PageType) {
        self.type = type
        super.init()

        // need this so the page / chapters can be set before the rest of the views are loaded
        switch type {
        case .info(let infoPageType):
            infoView = ReaderInfoPageView(type: infoPageType == .previous ? .previous : .next)
        case .page:
            pageView = ReaderPageView2()
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

            self.zoomView = zoomView
            self.pageView = pageView
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
        }
        if let zoomView = zoomView, let pageView = pageView {
            NSLayoutConstraint.activate([
                zoomView.topAnchor.constraint(equalTo: view.topAnchor),
                zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
                zoomView.rightAnchor.constraint(equalTo: view.rightAnchor),
                zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                pageView.topAnchor.constraint(equalTo: zoomView.topAnchor),
                pageView.leftAnchor.constraint(equalTo: zoomView.leftAnchor),
                pageView.rightAnchor.constraint(equalTo: zoomView.rightAnchor),
                pageView.bottomAnchor.constraint(equalTo: zoomView.bottomAnchor)
            ])
        }
    }

    func setPage(_ page: Page) {
        guard !pageSet else { return }
        pageSet = true
        pageView?.setPage(page)
    }
}
