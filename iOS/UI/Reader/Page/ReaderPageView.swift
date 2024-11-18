//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit
import Nuke

class ReaderPageView: UIView {

    weak var delegate: ReaderPageViewDelegate?

    let imageView = UIImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    var maxWidth = false

    var imageTask: ImageTask?
    private var sourceId: String?

    private var completion: ((Bool) -> Void)?

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

    func hasOutstandingTask() -> Bool {
        imageTask != nil && imageTask?.state == .running
    }

    func setPage(_ page: Page, sourceId: String? = nil) async -> Bool {
        if sourceId != nil {
            self.sourceId = sourceId
        }
        if let urlString = page.imageURL, let url = URL(string: urlString) {
            return await setPageImage(url: url, sourceId: self.sourceId)
        } else if let base64 = page.base64 {
            return await setPageImage(base64: base64, key: page.hashValue)
        } else {
            return false
        }
    }

    func setPageImage(url: URL, sourceId: String? = nil) async -> Bool {
        if imageView.image == nil {
            progressView.setProgress(value: 0, withAnimation: false)
            progressView.isHidden = false
        }

        let request: ImageRequest

        if let imageTask = imageTask {
            switch imageTask.state {
            case .running:
                if completion != nil {
                    completion!(imageView.image != nil)
                }
                return await withCheckedContinuation({ continuation in
                    self.completion = { success in
                        self.completion = nil
                        continuation.resume(returning: success)
                    }
                })
            case .completed:
                if imageView.image == nil {
                    request = imageTask.request
                } else {
                    return true
                }
            case .cancelled:
                request = imageTask.request
            }
        } else {
            var urlRequest = URLRequest(url: url)

            if
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
            }

            var processors: [ImageProcessing] = []
            if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                processors.append(CropBordersProcessor())
            }
            if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                processors.append(DownsampleProcessor(width: UIScreen.main.bounds.width))
            }

            request = ImageRequest(
                urlRequest: urlRequest,
                processors: processors
            )
        }

        return await startImageTask(request)
    }

    func startImageTask(_ request: ImageRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            imageTask = ImagePipeline.shared.loadImage(
                with: request,
                progress: { [weak self] _, completed, total in
                    guard let self else { return }
                    self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
                },
                completion: { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        imageView.image = response.image
                        fixImageSize()
                        completion?(true)
                        continuation.resume(returning: true)
                    case .failure:
                        completion?(false)
                        continuation.resume(returning: false)
                    }
                    progressView.isHidden = true
                }
            )
        }
    }

    func setPageImage(base64: String, key: Int) async -> Bool {
        let request = ImageRequest(id: String(key), data: { Data() })

        // TODO: can we show decoding progress?
        progressView.setProgress(value: 0, withAnimation: false)
        progressView.isHidden = false

        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            imageView.image = imageContainer?.image
            progressView.isHidden = true
            fixImageSize()
            return true
        }

        if let data = Data(base64Encoded: base64) {
            if var image = UIImage(data: data) {
                if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                    let processor = CropBordersProcessor()
                    let processedImage = processor.process(image)
                    if let processedImage = processedImage {
                        image = processedImage
                    }
                }
                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    let processor = DownsampleProcessor(width: UIScreen.main.bounds.width)
                    let processedImage = processor.process(image)
                    if let processedImage = processedImage {
                        image = processedImage
                    }
                }
                ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
                imageView.image = image
                progressView.isHidden = true
                fixImageSize()
                return true
            }
        }

        progressView.isHidden = true

        return false
    }

    // match image constraints with image size
    func fixImageSize() {
        guard imageView.image != nil else { return }

        imageHeightConstraint?.isActive = false
        imageWidthConstraint?.isActive = false

        if
            !maxWidth,
            case let height = imageView.image!.size.height * (bounds.width / imageView.image!.size.width),
            height > bounds.height || UIScreen.main.bounds.width > UIScreen.main.bounds.height // fix for double pages
        {
            // max height, variable width
            let multiplier = imageView.image!.size.width / imageView.image!.size.height
            imageWidthConstraint = imageView.widthAnchor.constraint(
                equalTo: imageView.heightAnchor,
                multiplier: multiplier
            )
            imageHeightConstraint = imageView.heightAnchor.constraint(equalTo: heightAnchor)
        } else {
            // max width, variable height
            let multiplier = imageView.image!.size.height / imageView.image!.size.width
            imageWidthConstraint = imageView.widthAnchor.constraint(equalTo: widthAnchor)
            imageHeightConstraint = imageView.heightAnchor.constraint(
                equalTo: imageView.widthAnchor,
                multiplier: multiplier
            )
        }
        imageWidthConstraint?.isActive = true
        imageHeightConstraint?.isActive = true
    }
}
