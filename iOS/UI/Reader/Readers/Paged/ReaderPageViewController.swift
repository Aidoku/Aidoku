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

    private lazy var reloadButton = {
        let reloadButton = UIButton(type: .roundedRect)
        reloadButton.isHidden = true
        reloadButton.setTitle(NSLocalizedString("RELOAD", comment: ""), for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        reloadButton.configuration = .borderless()
        reloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        return reloadButton
    }()

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
    private var sourceId: String?
    var imageAspectRatio: CGFloat? // Aspect ratio of the image, > 1 means wide image

    /// Callback when image aspect ratio is updated
    var onAspectRatioUpdated: (() -> Void)?

    /// Callback when image loading is complete and wide image status is determined
    var onImageisWideImage: ((Bool) -> Void)?

    init(type: PageType) {
        self.type = type
        super.init()

        // need this so the page / chapters can be set before the rest of the views are loaded
        switch type {
        case .info(let infoPageType):
            infoView = ReaderInfoPageView(type: infoPageType == .previous ? .previous : .next)
        case .page:
            pageView = ReaderPageView(parent: self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        switch type {
            case .info:
                // info view
                guard let infoView else { return }
                infoView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(infoView)

            case .page:
                // zoom view
                let zoomView = ZoomableScrollView(frame: view.bounds)
                zoomView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(zoomView)

                // page view
                guard let pageView else { return }
                pageView.translatesAutoresizingMaskIntoConstraints = false
                zoomView.addSubview(pageView)
                zoomView.zoomView = pageView

                view.addSubview(reloadButton)

                self.zoomView = zoomView
        }
    }

    override func constrain() {
        if let infoView {
            NSLayoutConstraint.activate([
                infoView.topAnchor.constraint(equalTo: view.topAnchor),
                infoView.leftAnchor.constraint(equalTo: view.leftAnchor),
                infoView.rightAnchor.constraint(equalTo: view.rightAnchor),
                infoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else if let zoomView, let pageView {
            NSLayoutConstraint.activate([
                zoomView.topAnchor.constraint(equalTo: view.topAnchor),
                zoomView.leftAnchor.constraint(equalTo: view.leftAnchor),
                zoomView.rightAnchor.constraint(equalTo: view.rightAnchor),
                zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                pageView.widthAnchor.constraint(equalTo: zoomView.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.heightAnchor),

                reloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    func setPage(_ page: Page, sourceId: String? = nil) {
        guard !pageSet, let pageView else { return }
        pageSet = true
        self.page = page
        self.sourceId = sourceId
        reloadButton.isHidden = true
        zoomView?.zoomEnabled = false
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId)
            zoomView?.zoomEnabled = result
            reloadButton.isHidden = result

            // Update aspect ratio
            let oldAspectRatio = imageAspectRatio
            if result, let image = pageView.imageView.image {
                imageAspectRatio = image.size.width / image.size.height
            } else {
                imageAspectRatio = nil
            }

            // Notify if aspect ratio changed and became wide image
            if oldAspectRatio != imageAspectRatio && isWideImage {
                onAspectRatioUpdated?()
            }

            // Notify when image loading is complete with wide image status
            onImageisWideImage?(isWideImage)
        }
    }

    @objc func reload() {
        guard let page else { return }
        pageSet = false
        reloadButton.isHidden = true
        pageView?.progressView.setProgress(value: 0, withAnimation: false)
        pageView?.progressView.isHidden = false
        setPage(page, sourceId: sourceId)
    }

    func clearPage() {
        pageSet = false
        pageView?.imageView.image = nil
        zoomView?.zoomEnabled = false
        imageAspectRatio = nil
    }

    /// Check if this is a wide image (aspect ratio > 1)
    var isWideImage: Bool {
        guard let imageAspectRatio else { return false }
        return imageAspectRatio > 1
    }
}
