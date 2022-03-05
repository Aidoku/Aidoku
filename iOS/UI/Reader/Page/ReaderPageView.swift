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
    let activityIndicator = UIActivityIndicatorView(style: .medium)
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
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

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

        activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

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
            activityIndicator.alpha = 1
            activityIndicator.startAnimating()
            currentUrl = nil
            setPageImage(url: url)
        }
    }

    func setPageImage(url: String) {
        guard currentUrl != url else { return }
        currentUrl = url

        DispatchQueue.main.async {
            let processor = DownsamplingImageProcessor(size: UIScreen.main.bounds.size)
            let retry = DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(0.1))
            self.imageView.kf.setImage(
                with: URL(string: url),
                options: [
                    .cacheOriginalImage,
                    .processor(processor),
                    .scaleFactor(UIScreen.main.scale),
                    .transition(.fade(0.3)),
                    .retryStrategy(retry)
                ]
            ) { result in
                switch result {
                case .success:
                    self.activityIndicator.stopAnimating()
                    self.activityIndicator.isHidden = true
                    self.reloadButton.alpha = 0
                    self.updateZoomBounds()
                case .failure:
                    self.activityIndicator.alpha = 0
                    self.reloadButton.alpha = 1
                }
            }
        }
    }
}
