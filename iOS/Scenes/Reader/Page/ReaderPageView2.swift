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

    private var sourceId: String?
    var checkForRequestModifier = true

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
            progressView.widthAnchor.constraint(equalToConstant: 40),
            progressView.heightAnchor.constraint(equalToConstant: 40),
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
        guard let urlString = page.imageURL, let url = URL(string: urlString) else { return false }
        return await setPageImage(url: url, sourceId: sourceId ?? self.sourceId)
    }

    func setPageImage(url: URL, sourceId: String? = nil) async -> Bool {
        var urlRequest = URLRequest(url: url)

        if checkForRequestModifier,
           let sourceId = sourceId,
           let source = SourceManager.shared.source(for: sourceId),
           source.handlesImageRequests,
           let request = try? await source.getImageRequest(url: url.absoluteString) {

            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
            checkForRequestModifier = false
        }

        let processors: [ImageProcessing]
        if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") && UIScreen.main.bounds.width > 0 {
            processors = [DownsampleProcessor(width: UIScreen.main.bounds.width)]
        } else {
            processors = []
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors
        )

        return await withCheckedContinuation({ continuation in
            NukeExtensions.loadImage(
                with: request,
                into: imageView,
                progress: { _, completed, total in
                    self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
                },
                completion: { result in
                    self.progressView.isHidden = true
                    switch result {
                    case .success:
                        // size image width properly
                        let multiplier = (self.imageView.image?.size.width ?? 0) / (self.imageView.image?.size.height ?? 1)
                        self.imageWidthConstraint?.isActive = false
                        self.imageWidthConstraint = self.imageView.widthAnchor.constraint(
                            equalTo: self.imageView.heightAnchor,
                            multiplier: multiplier
                        )
                        self.imageWidthConstraint?.isActive = true

                        continuation.resume(returning: true)

                    case .failure:
                        continuation.resume(returning: false)
                    }
                }
            )
        })
    }
}
