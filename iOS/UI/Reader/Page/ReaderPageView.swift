//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/7/22.
//

import UIKit
import Kingfisher

protocol ReaderPageViewDelegate: AnyObject {
    func imageLoaded(result: Result<RetrieveImageResult, KingfisherError>)
}

class ReaderPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    var sourceId: String

    var zoomableView = ZoomableScrollView(frame: UIScreen.main.bounds)
    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let reloadButton = UIButton(type: .roundedRect)

    var imageViewHeightConstraint: NSLayoutConstraint?

    var currentUrl: String?
    var cacheKey: String?

    var zoomEnabled = true {
        didSet {
            zoomableView.zoomEnabled = zoomEnabled
            if zoomEnabled {
                imageViewHeightConstraint?.isActive = false
                imageViewHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
                imageViewHeightConstraint?.isActive = true
            } else {
                imageViewHeightConstraint?.isActive = false
                imageViewHeightConstraint = imageView.heightAnchor.constraint(equalTo: zoomableView.heightAnchor)
                imageViewHeightConstraint?.isActive = true
            }
        }
    }

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

        zoomableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomableView)

        imageView.frame = UIScreen.main.bounds
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        zoomableView.addSubview(imageView)

        zoomableView.zoomView = imageView

        reloadButton.alpha = 0
        reloadButton.setTitle("Reload", for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        addSubview(reloadButton)

        activateConstraints()
    }

    func activateConstraints() {
        zoomableView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        zoomableView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        zoomableView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        zoomableView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        imageView.widthAnchor.constraint(equalTo: zoomableView.widthAnchor).isActive = true
        imageViewHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        imageViewHeightConstraint?.isActive = true
        imageView.centerXAnchor.constraint(equalTo: zoomableView.centerXAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: zoomableView.centerYAnchor).isActive = true

        reloadButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        progressView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        progressView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        progressView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        progressView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    func updateZoomBounds() {
        if zoomEnabled {
            var height = (imageView.image?.size.height ?? 0) / (imageView.image?.size.width ?? 1) * imageView.bounds.width
            if height > zoomableView.bounds.height {
                height = zoomableView.bounds.height
            }
            imageViewHeightConstraint?.constant = height
        } else {
            imageViewHeightConstraint?.constant = 0
        }
        zoomableView.contentSize = imageView.bounds.size
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

    @MainActor
    func setPageImage(url: String) async {
        if currentUrl == url && imageView.image != nil { return }
        currentUrl = url

        let request = try? await SourceManager.shared.source(for: sourceId)?.actor.getImageRequest(url: currentUrl ?? "")

        // Run the image loading code immediately on the main actor
        await MainActor.run {
            let userAgentModifier = AnyModifier { urlRequest in
                var r = urlRequest
                for (key, value) in request?.headers ?? [:] {
                    r.setValue(value, forHTTPHeaderField: key)
                }
                if let body = request?.body { r.httpBody = body }
                return r
            }
            let retry = DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(0.1))
            var kfOptions: [KingfisherOptionsInfoItem] = [
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry),
                .requestModifier(userAgentModifier)
            ]

            if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                let downsampleProcessor = DownsamplingImageProcessor(size: UIScreen.main.bounds.size)
                kfOptions += [.processor(downsampleProcessor), .cacheOriginalImage]
            }

            imageView.kf.setImage(
                with: URL(string: url),
                options: kfOptions,
                progressBlock: { receivedSize, totalSize in
                    self.progressView.setProgress(value: Float(receivedSize) / Float(totalSize), withAnimation: false)
                },
                completionHandler: { result in
                    switch result {
                    case .success(let imageResult):
                        self.cacheKey = imageResult.source.cacheKey
                        if self.progressView.progress != 1 {
                            self.progressView.setProgress(value: 1, withAnimation: true)
                        }
                        self.progressView.isHidden = true
                        self.reloadButton.alpha = 0
                        self.updateZoomBounds()
                    case .failure(let error):
                        // If the error isn't part of the current task, we don't care.
                        if error.isNotCurrentTask || error.isTaskCancelled {
                            return
                        }

                        if self.zoomEnabled {
                            self.progressView.alpha = 0
                            self.reloadButton.alpha = 1
                        }
                    }
                    self.delegate?.imageLoaded(result: result)
                }
            )
        }
    }
}
