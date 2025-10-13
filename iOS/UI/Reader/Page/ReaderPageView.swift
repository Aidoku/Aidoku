//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import Gifu
import MarkdownUI
import Nuke
import SwiftUI
import ZIPFoundation

class ReaderPageView: UIView {

    weak var parent: UIViewController?

    let imageView = GIFImageView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))

    private var textView: UIHostingController<MarkdownView>?

    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var imageTask: ImageTask?
    private var sourceId: String?

    private var completion: ((Bool) -> Void)?

    // MARK: - Reload functionality properties
    private var currentPage: Page?
    private var currentImageRequest: ImageRequest?

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    convenience init(parent: UIViewController?) {
        self.init()
        self.parent = parent
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
        // Store current page data for reload functionality
        self.currentPage = page

        if sourceId != nil {
            self.sourceId = sourceId
        }

        if let image = page.image {
            imageView.image = image
            fixImageSize()
            return true
        } else if let zipURL = page.zipURL, let url = URL(string: zipURL), let filePath = page.imageURL {
            return await setPageImage(zipURL: url, filePath: filePath)
        } else if let urlString = page.imageURL, let url = URL(string: urlString) {
            return await setPageImage(url: url, context: page.context, sourceId: self.sourceId)
        } else if let base64 = page.base64 {
            return await setPageImage(base64: base64, key: page.hashValue)
        } else if let text = page.text {
            setPageText(text: text)
            return true
        } else {
            return false
        }
    }

    func setPageImage(url: URL, context: PageContext? = nil, sourceId: String? = nil) async -> Bool {
        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        let request: ImageRequest

        if let imageTask {
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
            let urlRequest = if let sourceId, let source = SourceManager.shared.source(for: sourceId) {
                await source.getModifiedImageRequest(url: url, context: context)
            } else {
                URLRequest(url: url)
            }

            var processors: [ImageProcessing] = []
            var usePageProcessor = false
            if
                let sourceId,
                let newSource = SourceManager.shared.source(for: sourceId)
            {
                // only process pages if the source supports it and the image isn't downloaded
                if newSource.features.processesPages, !url.isFileURL {
                    processors.append(PageInterceptorProcessor(source: newSource))
                    usePageProcessor = true
                }
            }
            if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                processors.append(CropBordersProcessor())
            }
            if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                processors.append(DownsampleProcessor(width: UIScreen.main.bounds.width))
            } else if UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
                processors.append(UpscaleProcessor())
            }

            request = ImageRequest(
                urlRequest: urlRequest,
                processors: processors,
                userInfo: [.contextKey: context ?? [:], .processesKey: usePageProcessor]
            )
        }

        // Store current image request for reload functionality
        self.currentImageRequest = request

        if imageView.image == nil {
            progressView.setProgress(value: 0, withAnimation: false)
            progressView.isHidden = false
        }

        return await startImageTask(request)
    }

    private func startImageTask(_ request: ImageRequest) async -> Bool {
        imageTask = ImagePipeline.shared.loadImage(
            with: request,
            progress: { [weak self] _, completed, total in
                guard let self else { return }
                self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
            },
            completion: { _ in }
        )
        // hide progress view when task completes
        defer {
            progressView.isHidden = true
            imageTask = nil
        }
        do {
            let response = try await imageTask?.response
            guard let response else {
                return false
            }
            imageView.image = response.image
            if response.container.type == .gif, let data = response.container.data {
                imageView.animate(withGIFData: data)
            }
            fixImageSize()
            completion?(true)
            return true
        } catch {
            let error = error as? ImagePipeline.Error

            // we can still send to image processor even if the request failed
            if request.userInfo[.processesKey] as? Bool == true {
                let processor = request.processors.first(where: { $0 is PageInterceptorProcessor }) as? PageInterceptorProcessor
                if let processor {
                    let result: Nuke.ImageContainer?
                    switch error {
                        case .dataLoadingFailed, .dataIsEmpty, .decodingFailed:
                            result = await Task.detached {
                                try? processor.processWithoutImage(request: request)
                            }.value
                        default:
                            result = nil
                    }
                    if let result {
                        imageView.image = result.image
                        if result.type == .gif, let data = result.data {
                            imageView.animate(withGIFData: data)
                        }
                        fixImageSize()
                        completion?(true)
                        return true
                    }
                }
            }
            completion?(false)
            return false
        }
    }

    func setPageImage(base64: String, key: Int) async -> Bool {
        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        let request = ImageRequest(id: String(key), data: { Data() })

        // Store current image request for reload functionality
        self.currentImageRequest = request

        progressView.setProgress(value: 0, withAnimation: false)
        progressView.isHidden = false
        defer { progressView.isHidden = true }

        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            imageView.image = imageContainer?.image
            fixImageSize()
            return true
        }

        let image: UIImage? = await Task.detached {
            guard
                let imageData = Data(base64Encoded: base64),
                var image = UIImage(data: imageData)
            else {
                return nil
            }

            if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                let processor = CropBordersProcessor()
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            }
            if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                let processor = await DownsampleProcessor(width: UIScreen.main.bounds.width)
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            } else if UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
                let processor = UpscaleProcessor()
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            }

            return image
        }.value
        guard let image else { return false }

        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
        imageView.image = image
        fixImageSize()

        return true
    }

    func setPageImage(zipURL: URL, filePath: String) async -> Bool {
        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        var hasher = Hasher()
        hasher.combine(zipURL)
        hasher.combine(filePath)
        let key = String(hasher.finalize())

        let request = ImageRequest(id: key, data: { Data() })

        // Store current image request for reload functionality
        self.currentImageRequest = request

        progressView.setProgress(value: 0, withAnimation: false)
        progressView.isHidden = false
        defer { progressView.isHidden = true }

        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            imageView.image = imageContainer?.image
            fixImageSize()
            return true
        }

        let image: UIImage? = await Task.detached {
            do {
                var imageData = Data()
                let archive: Archive
                archive = try Archive(url: zipURL, accessMode: .read)
                guard let entry = archive[filePath]
                else {
                    return nil
                }
                _ = try archive.extract(
                    entry,
                    consumer: { data in
                        imageData.append(data)
                    }
                )
                guard var image = UIImage(data: imageData) else {
                    return nil
                }

                if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                    let processor = CropBordersProcessor()
                    if let processedImage = processor.process(image) {
                        image = processedImage
                    }
                }
                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    let processor = await DownsampleProcessor(width: UIScreen.main.bounds.width)
                    if let processedImage = processor.process(image) {
                        image = processedImage
                    }
                } else if UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
                    let processor = UpscaleProcessor()
                    if let processedImage = processor.process(image) {
                        image = processedImage
                    }
                }

                return image
            } catch {
                return nil
            }
        }.value
        guard let image else { return false }

        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
        imageView.image = image
        fixImageSize()

        return true
    }

    // match image constraints with image size
    func fixImageSize() {
        guard imageView.image != nil else { return }

        imageHeightConstraint?.isActive = false
        imageWidthConstraint?.isActive = false

        if
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

    func setPageText(text: String) {
        imageView.image = nil
        progressView.isHidden = true

        let view = MarkdownView(text)

        if let textView {
            textView.rootView = view
        } else {
            textView = UIHostingController(rootView: view)
            guard let textView else { return }
            if #available(iOS 16.0, *) {
                textView.sizingOptions = .intrinsicContentSize
            }
            if #available(iOS 16.4, *) {
                // fixes text being shifted when navbar is hidden/shown
                textView.safeAreaRegions = []
            }
            textView.view.translatesAutoresizingMaskIntoConstraints = false
            if let parent {
                parent.addChild(textView)
                textView.didMove(toParent: parent)
            }
            addSubview(textView.view)

            NSLayoutConstraint.activate([
                textView.view.topAnchor.constraint(equalTo: topAnchor),
                textView.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                // if the text string is too long, it'll just extend downwards out of bounds
                // we should probably make it scrollable as long as it doesn't mess with the existing swipe gesture
                textView.view.heightAnchor.constraint(greaterThanOrEqualTo: heightAnchor)
            ])
        }
    }

    // MARK: - Image Reload Functionality

    /// Reloads the current image by clearing its cache and re-fetching from the source
    @MainActor
    func reloadCurrentImage() async -> Bool {
        guard let currentPage else {
            return false
        }

        // Clear the cache for the current image
        clearCurrentImageCache()

        // Clear the current image to show loading state
        imageView.image = nil

        // Reload the image using the original page data
        return await setPage(currentPage, sourceId: sourceId)
    }

    /// Clears the cache entry for the current image
    private func clearCurrentImageCache() {
        guard let currentPage else { return }

        // Handle different image types
        if currentPage.imageURL != nil {
            // For URL-based images, use the stored request if available
            if let currentImageRequest {
                ImagePipeline.shared.cache.removeCachedImage(for: currentImageRequest)
            }
        }
        if currentPage.base64 != nil {
            // For base64 images
            let request = ImageRequest(id: String(currentPage.hashValue), data: { Data() })
            ImagePipeline.shared.cache.removeCachedImage(for: request)
        }
        if let zipURL = currentPage.zipURL, let url = URL(string: zipURL), let filePath = currentPage.imageURL {
            // For zip file images
            var hasher = Hasher()
            hasher.combine(url)
            hasher.combine(filePath)
            let key = String(hasher.finalize())
            let request = ImageRequest(id: key, data: { Data() })
            ImagePipeline.shared.cache.removeCachedImage(for: request)
        }
    }

    /// Splits the current image into left and right halves
    func splitImage() -> (left: UIImage?, right: UIImage?) {
        guard let image = imageView.image else { return (nil, nil) }

        let imageSize = image.size
        let imageScale = image.scale

        // Calculate the split point (middle of the image)
        let splitX = imageSize.width / 2

        // Create left half rect
        let leftRect = CGRect(x: 0, y: 0, width: splitX, height: imageSize.height)

        // Create right half rect
        let rightRect = CGRect(x: splitX, y: 0, width: splitX, height: imageSize.height)

        // Extract left half
        guard let leftCGImage = image.cgImage?.cropping(to: leftRect) else {
            return (nil, nil)
        }
        let leftImage = UIImage(cgImage: leftCGImage, scale: imageScale, orientation: image.imageOrientation)

        // Extract right half
        guard let rightCGImage = image.cgImage?.cropping(to: rightRect) else {
            return (nil, nil)
        }
        let rightImage = UIImage(cgImage: rightCGImage, scale: imageScale, orientation: image.imageOrientation)

        return (leftImage, rightImage)
    }
}
