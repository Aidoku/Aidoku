//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/7/22.
//

import UIKit
import Nuke

protocol ReaderPageViewDelegate: AnyObject {
    func imageLoaded(key: String, image: UIImage)
}

class ReaderPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    var readingMode: MangaViewer
    var backward: Bool { readingMode == .rtl }

    var sourceId: String

    var zoomableView = ZoomableScrollView(frame: UIScreen.main.bounds)
    var multiView = UIStackView()
    var imageViews: [UIImageView] = []
    var progressViews: [CircularProgressView] = []
    var reloadButtons: [UIButton] = []

    var multiViewWidthConstraint: NSLayoutConstraint?
    var multiViewHeightConstraint: NSLayoutConstraint?

    var currentUrls: [Int: String?] = [:]
    var cacheKeys: [Int: String?] = [:]
    var imageSizes: [Int: CGSize] = [:]

//    var requestModifier: AnyModifier?
    var shouldCheckForRequestModifer = true

    var numPages: Int {
        didSet {
            imageViews.forEach({ $0.removeFromSuperview() })
            progressViews.forEach({ $0.removeFromSuperview() })
            reloadButtons.forEach({ $0.removeFromSuperview() })
            imageViews = []
            progressViews = []
            reloadButtons = []
            currentUrls = [:]
            cacheKeys = [:]
            imageSizes = [:]
            multiView = UIStackView()
            for _ in 0..<numPages {
                let imageView = UIImageView()
                imageViews.append(imageView)
                multiView.addArrangedSubview(imageView)
                progressViews.append(CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40)))
                reloadButtons.append(UIButton(type: .roundedRect))
            }
            configureViews()
        }
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
        self.numPages = max(1, pages)
        super.init(frame: UIScreen.main.bounds)
        for _ in 0..<numPages {
            let imageView = UIImageView()
            imageViews.append(imageView)
            multiView.addArrangedSubview(imageView)
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
        imageViews.enumerated().forEach { index, view in
            view.frame = multiView.frame.splitWidth(into: numPages, index: index)
            view.contentMode = .scaleAspectFit
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
        multiView.layoutSubviews()
    }

    func activateConstraints() {
        zoomableView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        zoomableView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        zoomableView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        zoomableView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        multiViewWidthConstraint = multiView.widthAnchor.constraint(equalToConstant: bounds.width)
        multiViewWidthConstraint?.isActive = true
        multiViewHeightConstraint = multiView.heightAnchor.constraint(equalToConstant: 0)
        multiViewHeightConstraint?.isActive = true
        multiView.centerXAnchor.constraint(equalTo: zoomableView.centerXAnchor).isActive = true
        multiView.centerYAnchor.constraint(equalTo: zoomableView.centerYAnchor).isActive = true
        multiView.distribution = .fillProportionally

        for (i, reloadButton) in reloadButtons.enumerated() {
            let offset = bounds.width / CGFloat(numPages) * (CGFloat(i) + 0.5) - bounds.width / 2
            reloadButton.centerXAnchor.constraint(equalTo: multiView.centerXAnchor, constant: offset).isActive = true
            reloadButton.centerYAnchor.constraint(equalTo: imageViews[i].centerYAnchor).isActive = true
        }

        for (i, progressView) in progressViews.enumerated() {
            let offset = bounds.width / CGFloat(numPages) * (CGFloat(i) + 0.5) - bounds.width / 2
            progressView.widthAnchor.constraint(equalToConstant: 40).isActive = true
            progressView.heightAnchor.constraint(equalToConstant: 40).isActive = true
            progressView.centerXAnchor.constraint(equalTo: multiView.centerXAnchor, constant: offset).isActive = true
            progressView.centerYAnchor.constraint(equalTo: imageViews[i].centerYAnchor).isActive = true
        }
    }

    func updateZoomBounds() {
        multiViewHeightConstraint?.constant = zoomEnabled ? zoomableView.bounds.height : 0
        zoomableView.contentSize = multiView.bounds.size
        let totalWidth = imageSizes.reduce(CGFloat(0), { $0 + $1.value.width / $1.value.height * bounds.height })
        multiViewWidthConstraint?.constant = min(totalWidth, bounds.width)
        multiView.layoutSubviews()
    }

    func updateImageSize(page: Int) {
        guard let image = imageViews[page].image else { return }
        imageSizes[page] = image.size
        let totalWidth = imageSizes.reduce(CGFloat(0), { $0 + $1.value.width / $1.value.height * bounds.height })
        multiViewWidthConstraint?.constant = min(totalWidth, bounds.width)
        multiView.layoutSubviews()
    }

    @objc func reload(sender: UIButton) {
        if let pageIndex = reloadButtons.firstIndex(where: { $0 == sender }), let url = currentUrls[pageIndex] {
            sender.alpha = 0
            progressViews[pageIndex].alpha = 1
            currentUrls[pageIndex] = nil
            Task {
                await setPageImage(url: url ?? "", page: pageIndex)
            }
        }
    }

    func setPage(page: Page, index: Int) {
        if let url = page.imageURL {
            Task {
                await setPageImage(url: url, key: page.key, page: index)
            }
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
        imageViews[safe: page]?.image = image
        if progressViews[page].progress != 1 {
            progressViews[page].setProgress(value: 1, withAnimation: true)
        }
        progressViews[page].isHidden = true
        reloadButtons[page].alpha = 0
        updateZoomBounds()
        if let key = key, let image = image {
            updateImageSize(page: page)
            delegate?.imageLoaded(key: key, image: image)
        }
    }

    func setPageImage(image: UIImage, key: String? = nil, page: Int) {
        guard let imageView = self.multiView.subviews[safe: page] as? UIImageView else { return }
        imageView.image = image
        self.updateImageSize(page: page)
        self.updateZoomBounds()
        if let key = key {
            self.delegate?.imageLoaded(key: key, image: image)
        }
    }

    func setPageImage(url: String, key: String? = nil, page: Int) async {
        guard
            let url = URL(string: url),
            let imageView = self.multiView.subviews[safe: page] as? UIImageView
        else {
            (self.multiView.subviews[safe: page] as? UIImageView)?.image = nil
            return
        }

        if let image = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url)) {
            setPageImage(image: image.image, page: page)
            return
        }

        var urlRequest = URLRequest(url: url)

        if shouldCheckForRequestModifer,
           let source = SourceManager.shared.source(for: sourceId),
           source.handlesImageRequests,
           let request = try? await source.getImageRequest(url: url.absoluteString) {

            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
            shouldCheckForRequestModifer = false
        }

        var request = ImageRequest(urlRequest: urlRequest)

        if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
            request.processors = [.resize(width: UIScreen.main.bounds.width)]
        }

        ImagePipeline.shared.loadImage(with: request) { result in
            if let response = try? result.get() {
                imageView.image = response.image
                self.updateImageSize(page: page)
                self.updateZoomBounds()
                if let key = key {
                    self.delegate?.imageLoaded(key: key, image: response.image)
                }
            }
        }
    }
}
