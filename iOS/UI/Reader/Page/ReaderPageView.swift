//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/7/22.
//

import UIKit
import Kingfisher

protocol ReaderPageViewDelegate: AnyObject {
    func imageLoaded(key: String, image: UIImage)
}

class ReaderPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    var readingMode: MangaViewer
    var backward: Bool { readingMode == .rtl }

    var sourceId: String

    var zoomableView = ZoomableScrollView(frame: UIScreen.main.bounds)
    let multiView = UIView()

    var progressViews: [CircularProgressView] = []
    var reloadButtons: [UIButton] = []

    var multiViewHeightConstraint: NSLayoutConstraint?

    var currentUrls: [Int: String?] = [:]
    var cacheKeys: [Int: String?] = [:]

    var numPages: Int {
        multiView.subviews.count
    }

    var zoomEnabled = true {
        didSet {
            zoomableView.zoomEnabled = zoomEnabled
            if zoomEnabled {
                multiViewHeightConstraint?.isActive = false
                multiViewHeightConstraint = multiView.heightAnchor.constraint(equalToConstant: 0)
                multiViewHeightConstraint?.isActive = true
            } else {
                multiViewHeightConstraint?.isActive = false
                multiViewHeightConstraint = multiView.heightAnchor.constraint(equalTo: zoomableView.heightAnchor)
                multiViewHeightConstraint?.isActive = true
            }
        }
    }

    init(sourceId: String, pages: Int = 1, mode: MangaViewer) {
        self.sourceId = sourceId
        self.readingMode = mode
        super.init(frame: UIScreen.main.bounds)
        for _ in 0..<max(1, pages) {
            multiView.addSubview(UIImageView())
            progressViews.append(CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
            reloadButtons.append(UIButton(type: .roundedRect))
        }
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureViews() {
        for progressView in progressViews {
            progressView.trackColor = .quaternaryLabel
            progressView.progressColor = tintColor
            progressView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(progressView)
        }

        zoomableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomableView)

        multiView.frame = UIScreen.main.bounds
        multiView.subviews.enumerated().forEach { index, view in
            view.frame = multiView.frame.splitWidth(into: numPages, index: index)
            (view as? UIImageView)?.contentMode = .scaleAspectFit
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = true
        }
        multiView.translatesAutoresizingMaskIntoConstraints = false
        zoomableView.addSubview(multiView)

        zoomableView.zoomView = multiView

        for reloadButton in reloadButtons {
            reloadButton.alpha = 0
            reloadButton.setTitle("Reload", for: .normal)
            reloadButton.addTarget(self, action: #selector(reload(sender:)), for: .touchUpInside)
            reloadButton.translatesAutoresizingMaskIntoConstraints = false
            reloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
            addSubview(reloadButton)
        }

        activateConstraints()
    }

    func activateConstraints() {
        zoomableView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        zoomableView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        zoomableView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        zoomableView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        multiView.widthAnchor.constraint(equalTo: zoomableView.widthAnchor).isActive = true
        multiViewHeightConstraint = multiView.heightAnchor.constraint(equalToConstant: 0)
        multiViewHeightConstraint?.isActive = true
        multiView.centerXAnchor.constraint(equalTo: zoomableView.centerXAnchor).isActive = true
        multiView.centerYAnchor.constraint(equalTo: zoomableView.centerYAnchor).isActive = true

        multiView.subviews.forEach { view in
            view.widthAnchor.constraint(equalTo: multiView.widthAnchor, multiplier: 1/CGFloat(numPages)).isActive = true
            view.heightAnchor.constraint(equalTo: multiView.heightAnchor).isActive = true
            view.centerYAnchor.constraint(equalTo: multiView.centerYAnchor).isActive = true
        }
        if numPages % 2 == 0 {
            multiView.subviews[numPages / 2 - 1].trailingAnchor.constraint(equalTo: multiView.centerXAnchor).isActive = true
            multiView.subviews[numPages / 2].leadingAnchor.constraint(equalTo: multiView.centerXAnchor).isActive = true
        } else {
            multiView.subviews[numPages / 2].centerXAnchor.constraint(equalTo: multiView.centerXAnchor).isActive = true
        }
        if numPages >= 3 {
            for i in (0..<(numPages / 2)).reversed() {
                multiView.subviews[i].trailingAnchor.constraint(equalTo: multiView.subviews[i + 1].leadingAnchor).isActive = true
                multiView.subviews[numPages-i-1].leadingAnchor.constraint(equalTo: multiView.subviews[numPages-i-2].trailingAnchor).isActive = true
            }
        }

        for (i, reloadButton) in reloadButtons.enumerated() {
            reloadButton.centerXAnchor.constraint(equalTo: multiView.subviews[i].centerXAnchor).isActive = true
            reloadButton.centerYAnchor.constraint(equalTo: multiView.subviews[i].centerYAnchor).isActive = true
        }

        for (i, progressView) in progressViews.enumerated() {
            progressView.widthAnchor.constraint(equalToConstant: 40).isActive = true
            progressView.heightAnchor.constraint(equalToConstant: 40).isActive = true
            progressView.centerXAnchor.constraint(equalTo: multiView.subviews[i].centerXAnchor).isActive = true
            progressView.centerYAnchor.constraint(equalTo: multiView.subviews[i].centerYAnchor).isActive = true
        }
    }

    func updateZoomBounds() {
        if zoomEnabled {
            var height = multiView.subviews.map({ view -> CGFloat in
                let imageView = view as? UIImageView
                return (imageView?.image?.size.height ?? 0) / (imageView?.image?.size.width ?? 1) * (imageView?.bounds.width ?? 1)
            }).max() ?? zoomableView.bounds.height
            if height > zoomableView.bounds.height {
                height = zoomableView.bounds.height
            }
            multiViewHeightConstraint?.constant = height
        } else {
            multiViewHeightConstraint?.constant = 0
        }
        zoomableView.contentSize = multiView.bounds.size
    }

    @objc func reload(sender: UIButton) {
        if let pageIndex = reloadButtons.firstIndex(where: { $0 == sender }), let url = currentUrls[pageIndex] {
            sender.alpha = 0
            progressViews[pageIndex].alpha = 1
            currentUrls[pageIndex] = nil
            setPageImage(url: url ?? "", page: pageIndex)
        }
    }

    func setPage(page: Page, index: Int) {
        if let url = page.imageURL {
            setPageImage(url: url, key: page.key, page: index)
        } else if let base64 = page.base64 {
            setPageImage(base64: base64, key: page.key, page: index)
        } else if let text = page.text {
            setPageText(text: text)
        }
    }

    func setPageText(text: String) {
        // TODO: support text
    }

    func setPageImage(base64: String, key: String, page: Int) {
        Task.detached {
            if let data = Data(base64Encoded: base64) {
                await self.setPageData(data: data, key: key, page: page)
            }
        }
    }

    @MainActor
    func setPageData(data: Data, key: String? = nil, page: Int) {
        let page = backward ? numPages - page - 1 : page
        currentUrls[page] = nil
        let image = UIImage(data: data)
        (multiView.subviews[safe: page] as? UIImageView)?.image = image
        if progressViews[page].progress != 1 {
            progressViews[page].setProgress(value: 1, withAnimation: true)
        }
        progressViews[page].isHidden = true
        reloadButtons[page].alpha = 0
        updateZoomBounds()
        if let key = key, let image = image {
            delegate?.imageLoaded(key: key, image: image)
        }
    }

    func setPageImage(url: String, key: String? = nil, page: Int) {
        let page = backward ? numPages - page - 1 : page
        if currentUrls[page] == url && (multiView.subviews[safe: page] as? UIImageView)?.image != nil { return }
        currentUrls[page] = url

        Task.detached {
            let requestModifier: AnyModifier?

            if let source = await SourceManager.shared.source(for: self.sourceId),
               source.handlesImageRequests,
               let request = try? await source.getImageRequest(url: url) {
                requestModifier = AnyModifier { urlRequest in
                    var r = urlRequest
                    for (key, value) in request.headers {
                        r.setValue(value, forHTTPHeaderField: key)
                    }
                    if let body = request.body { r.httpBody = body }
                    return r
                }
            } else {
                requestModifier = nil
            }

            Task { @MainActor in
                let retry = DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(0.1))
                var kfOptions: [KingfisherOptionsInfoItem] = [
                    .scaleFactor(UIScreen.main.scale),
                    .transition(.fade(0.3)),
                    .retryStrategy(retry),
                    .backgroundDecode
                ]
                if let requestModifier = requestModifier {
                    kfOptions.append(.requestModifier(requestModifier))
                }

                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    // provide larger height so the width of the image is always downsampled to screen width (for long strips)
                    let downsampleProcessor = DownsamplingImageProcessor(size: CGSize(width: UIScreen.main.bounds.width, height: 10000))
                    kfOptions += [.processor(downsampleProcessor), .cacheOriginalImage]
                }

                (self.multiView.subviews[safe: page] as? UIImageView)?.kf.setImage(
                    with: URL(string: url),
                    options: kfOptions,
                    progressBlock: { receivedSize, totalSize in
                        self.progressViews[page].setProgress(value: Float(receivedSize) / Float(totalSize), withAnimation: false)
                    },
                    completionHandler: { result in
                        switch result {
                        case .success(let imageResult):
                            if self.progressViews[page].progress != 1 {
                                self.progressViews[page].setProgress(value: 1, withAnimation: true)
                            }
                            self.progressViews[page].isHidden = true
                            self.reloadButtons[page].alpha = 0
                            self.updateZoomBounds()
                            if let key = key {
                                self.delegate?.imageLoaded(key: key, image: imageResult.image)
                            }
                        case .failure(let error):
                            // If the error isn't part of the current task, we don't care.
                            if error.isNotCurrentTask || error.isTaskCancelled {
                                return
                            }

                            if self.zoomEnabled {
                                self.progressViews[page].alpha = 0
                                self.reloadButtons[page].alpha = 1
                            }
                        }
                    }
                )
            }
        }
    }
}
