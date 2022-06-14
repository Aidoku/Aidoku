//
//  ReaderScrollPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/14/22.
//

import UIKit
import Kingfisher

class ReaderScrollPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    var sourceId: String

    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let reloadButton = UIButton(type: .roundedRect)

    var imageViewHeightConstraint: NSLayoutConstraint?

    var currentUrl: String?
    var currentTask: Kingfisher.DownloadTask?
    var requestModifier: AnyModifier?
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
            setPageImage(url: url)
        }
    }

    func setPage(page: Page) {
        if let url = page.imageURL {
            setPageImage(url: url, key: page.key)
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

    // swiftlint:disable:next cyclomatic_complexity
    func setPageImage(url: String, key: String? = nil) {
        if currentUrl == url && imageView.image != nil { return }

        if currentTask != nil {
            currentTask?.cancel()
            currentTask = nil
        }

        currentUrl = url

        Task { @MainActor in
            if shouldCheckForRequestModifer {
                if let source = SourceManager.shared.source(for: sourceId),
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
                shouldCheckForRequestModifer = false
            }

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

            currentTask = self.imageView.kf.setImage(
                with: URL(string: url),
                options: kfOptions,
                progressBlock: { receivedSize, totalSize in
                    self.progressView.setProgress(value: Float(receivedSize) / Float(totalSize), withAnimation: false)
                },
                completionHandler: { result in
                    self.currentTask = nil
                    switch result {
                    case .success(let imageResult):
                        if self.progressView.progress != 1 {
                            self.progressView.setProgress(value: 1, withAnimation: true)
                        }
                        self.progressView.isHidden = true
                        self.reloadButton.alpha = 0
                        if let key = key {
                            self.delegate?.imageLoaded(key: key, image: imageResult.image)
                        }
                    case .failure(let error):
                        // If the error isn't part of the current task, we don't care.
                        if error.isNotCurrentTask || error.isTaskCancelled {
                            return
                        }

                        self.progressView.alpha = 0
                        self.reloadButton.alpha = 1
                    }
                }
            )
        }
    }
}
