//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/7/22.
//

import UIKit
import Kingfisher

class ReaderPageView: UIView {

    var zoomableView = ZoomableScrollView(frame: UIScreen.main.bounds)
    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let reloadButton = UIButton(type: .roundedRect)

    var imageViewHeightConstraint: NSLayoutConstraint?

    var currentUrl: String?

    init() {
        super.init(frame: UIScreen.main.bounds)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureViews() {
        progressView.center = self.center
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = self.tintColor
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
        zoomableView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        zoomableView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true

        imageView.widthAnchor.constraint(equalTo: zoomableView.widthAnchor).isActive = true
        imageViewHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        imageViewHeightConstraint?.isActive = true
        imageView.centerXAnchor.constraint(equalTo: zoomableView.centerXAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: zoomableView.centerYAnchor).isActive = true

        reloadButton.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    func updateZoomBounds() {
        var height = (self.imageView.image?.size.height ?? 0) / (self.imageView.image?.size.width ?? 1) * self.imageView.bounds.width
        if height > zoomableView.bounds.height {
            height = zoomableView.bounds.height
        }
        self.imageViewHeightConstraint?.constant = height
        self.zoomableView.contentSize = self.imageView.bounds.size
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

    func setPageImage(url: String) async {
        guard currentUrl != url else { return }
        currentUrl = url

        // Run the image loading code immediately on the main actor
        await MainActor.run {
            let retry = DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(0.1))
            var kfOptions: [KingfisherOptionsInfoItem] = [
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry)
            ]

            if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                let downsampleProcessor = DownsamplingImageProcessor(size: UIScreen.main.bounds.size)
                kfOptions += [.processor(downsampleProcessor), .cacheOriginalImage]
            }

            self.imageView.kf.setImage(
                with: URL(string: url),
                options: kfOptions,
                progressBlock: { recievedSize, totalSize in
                    self.progressView.setProgress(value: Float(recievedSize) / Float(totalSize), withAnimation: false)
                },
                completionHandler: { result in
                    switch result {
                    case .success:
                        if self.progressView.progress != 1 {
                            self.progressView.setProgress(value: 1, withAnimation: true)
                        }
                        self.progressView.isHidden = true
                        self.reloadButton.alpha = 0
                        self.updateZoomBounds()
                    case .failure:
                        self.progressView.alpha = 0
                        self.reloadButton.alpha = 1
                    }
                }
            )
        }
    }
}
