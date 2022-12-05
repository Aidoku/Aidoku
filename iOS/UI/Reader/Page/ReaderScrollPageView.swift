//
//  ReaderScrollPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/14/22.
//

import UIKit
import Nuke

class ReaderScrollPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    var sourceId: String

    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let reloadButton = UIButton(type: .roundedRect)

    var imageViewHeightConstraint: NSLayoutConstraint?

    var currentUrl: String?
    var shouldCheckForRequestModifer = true

    init(sourceId: String) {
        self.sourceId = sourceId
        super.init(frame: UIScreen.main.bounds)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureViews() {
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        imageView.frame = UIScreen.main.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        reloadButton.alpha = 0
        reloadButton.setTitle("Reload", for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        addSubview(reloadButton)

        activateConstraints()
    }

    func activateConstraints() {
        imageView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        imageView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        imageView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        reloadButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        progressView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        progressView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        progressView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        progressView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    @objc func reload() {
        if let url = currentUrl {
            reloadButton.alpha = 0
            progressView.alpha = 1
            currentUrl = nil
            Task {
                await setPageImage(url: url)
            }
        }
    }

    func setPage(page: Page) {
        if let url = page.imageURL {
            Task {
                await setPageImage(url: url, key: page.key)
            }
        } else if let base64 = page.base64 {
            setPageImage(base64: base64, key: page.key)
        } else if let text = page.text {
            setPageText(text: text)
        }
    }

    func setPageText(text: String) {
        // TODO: support text
    }

    func setPageImage(base64: String, key: String) {
        Task.detached {
            if let data = Data(base64Encoded: base64) {
                await self.setPageData(data: data, key: key)
            }
        }
    }

    @MainActor
    func setPageData(data: Data, key: String? = nil) {
        currentUrl = nil
        let image = UIImage(data: data)
        imageView.image = image
        if progressView.progress != 1 {
            progressView.setProgress(value: 1, withAnimation: true)
        }
        progressView.isHidden = true
        reloadButton.alpha = 0
        if let key = key, let image = image {
            delegate?.imageLoaded(key: key, image: image)
        }
    }

    func setPageImage(image: UIImage, key: String? = nil) {
        if self.progressView.progress != 1 {
            self.progressView.setProgress(value: 1, withAnimation: true)
        }
        self.progressView.isHidden = true
        self.reloadButton.alpha = 0
        imageView.image = image
        if let key = key {
            self.delegate?.imageLoaded(key: key, image: image)
        }
    }

    func setPageImage(url: String, key: String? = nil) async {
        guard
            let url = URL(string: url)
        else {
            self.imageView.image = nil
            return
        }

        if let image = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url)) {
            imageView.image = image.image
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
                if self.progressView.progress != 1 {
                    self.progressView.setProgress(value: 1, withAnimation: true)
                }
                self.progressView.isHidden = true
                self.reloadButton.alpha = 0
                self.imageView.image = response.image
                if let key = key {
                    self.delegate?.imageLoaded(key: key, image: response.image)
                }
            } else {
                self.progressView.alpha = 0
                self.reloadButton.alpha = 1
            }
        }
    }
}
