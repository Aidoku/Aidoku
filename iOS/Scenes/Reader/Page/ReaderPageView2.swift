//
//  ReaderPageView2.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit
import Nuke
import NukeExtensions

class ReaderPageView2: UIView {

    weak var delegate: ReaderPageViewDelegate?

    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    var imageWidthConstraint: NSLayoutConstraint?
    var maxWidth = false

    private var sourceId: String?
    private var checkForRequestModifier = true

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        imageWidthConstraint = imageView.widthAnchor.constraint(equalTo: widthAnchor)
        imageWidthConstraint?.isActive = true
    }

    func constrain() {
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: progressView.frame.width),
            progressView.heightAnchor.constraint(equalToConstant: progressView.frame.height),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func setPage(_ page: Page, sourceId: String? = nil) async -> Bool {
        if sourceId != nil {
            self.sourceId = sourceId
        }
        if let urlString = page.imageURL, let url = URL(string: urlString) {
            return await setPageImage(url: url, sourceId: sourceId ?? self.sourceId)
        } else if let base64 = page.base64 {
            return await setPageImage(base64: base64, key: page.hashValue)
        } else {
            return false
        }
    }

    func setPageImage(url: URL, sourceId: String? = nil) async -> Bool {
        var urlRequest = URLRequest(url: url)

        self.progressView.setProgress(value: 0, withAnimation: false)
        self.progressView.alpha = 1

        if
            checkForRequestModifier,
            let sourceId = sourceId,
            let source = SourceManager.shared.source(for: sourceId),
            source.handlesImageRequests,
            let request = try? await source.getImageRequest(url: url.absoluteString)
        {
            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
            checkForRequestModifier = false
        }

        let shouldDownscale = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let processors = [DownsampleProcessor(width: UIScreen.main.bounds.width, downscale: shouldDownscale)]

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors
        )

        return await withCheckedContinuation({ continuation in
            _ = NukeExtensions.loadImage(
                with: request,
                into: imageView,
                progress: { _, completed, total in
                    self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
                },
                completion: { result in
                    self.progressView.alpha = 0
                    switch result {
                    case .success:
                        self.fixImageWidth()
                        continuation.resume(returning: true)

                    case .failure:
                        continuation.resume(returning: false)
                    }
                }
            )
        })
    }

    func setPageImage(base64: String, key: Int) async -> Bool {
        let request = ImageRequest(id: String(key), data: { Data() })
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            imageView.image = imageContainer?.image
            progressView.alpha = 0
            fixImageWidth()
            return true
        }
        if let data = Data(base64Encoded: base64) {
            if let image = UIImage(data: data) {
                let shouldDownscale = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
                let processor = DownsampleProcessor(width: UIScreen.main.bounds.width, downscale: shouldDownscale)
                let processedImage = processor.process(image)
                if let processedImage = processedImage {
                    ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: processedImage), for: request)
                    imageView.image = processedImage
                    progressView.alpha = 0
                    fixImageWidth()
                    return true
                }
            }
        }
        return false
    }

    // size image width properly
    func fixImageWidth() {
        if !self.maxWidth {
            let multiplier = (self.imageView.image?.size.width ?? 1) / (self.imageView.image?.size.height ?? 1)
            self.imageWidthConstraint?.isActive = false
            self.imageWidthConstraint = self.imageView.widthAnchor.constraint(
                equalTo: self.imageView.heightAnchor,
                multiplier: multiplier
            )
            self.imageWidthConstraint?.isActive = true
        }
    }
}
