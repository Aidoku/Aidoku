//
//  ReaderWebtoonPageNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/1/23.
//

import AidokuRunner
import AsyncDisplayKit
import Gifu
import Nuke
import SwiftUI
import ZIPFoundation

class ReaderWebtoonPageNode: BaseObservingCellNode {
    let source: AidokuRunner.Source?
    let page: Page

    weak var delegate: ReaderWebtoonViewController?

    var image: UIImage? {
        didSet {
            guard let image else { return }
            ratio = image.size.height / image.size.width
        }
    }
    var text: String?
    var ratio: CGFloat?
    private var loading = false

    // MARK: - Reload functionality properties
    private var currentImageRequest: ImageRequest?

    var pillarbox = UserDefaults.standard.bool(forKey: "Reader.pillarbox")
    var pillarboxAmount = CGFloat(UserDefaults.standard.double(forKey: "Reader.pillarboxAmount"))
    var pillarboxOrientation = UserDefaults.standard.string(forKey: "Reader.pillarboxOrientation")

    static let defaultRatio: CGFloat = 1.435

    var progressView: CircularProgressView {
        (progressNode.view as? CircularProgressView)!
    }

    lazy var imageNode: GIFImageNode = {
        let node = GIFImageNode()
        node.alpha = 0
        node.contentMode = .scaleToFill
        node.shouldAnimateSizeChanges = false
        node.isUserInteractionEnabled = false
        return node
    }()

    lazy var textNode = HostingNode(
        parentViewController: delegate,
        content: MarkdownView(page.text ?? "")
    )

    lazy var progressNode = ASCellNode(viewBlock: {
        CircularProgressView()
    })

    init(
        source: AidokuRunner.Source?,
        page: Page
    ) {
        self.source = source
        self.page = page
        super.init()
        automaticallyManagesSubnodes = true
        shouldAnimateSizeChanges = false
        addObserver(forName: "Reader.pillarbox") { [weak self] notification in
            self?.pillarbox = notification.object as? Bool ?? false
            self?.transition()
        }
        addObserver(forName: "Reader.pillarboxAmount") { [weak self] notification in
            guard let doubleValue = notification.object as? Double else { return }
            self?.pillarboxAmount = CGFloat(doubleValue)
            self?.transition()
        }
        addObserver(forName: "Reader.pillarboxOrientation") { [weak self] notification in
            self?.pillarboxOrientation = notification.object as? String ?? "both"
            self?.transition()
        }
    }

    override func didEnterDisplayState() {
        super.didEnterDisplayState()
        displayPage()
    }

    override func didExitDisplayState() {
        super.didExitDisplayState()
        guard !isVisible else { return }
        // don't hide images if zooming in/out
        if let delegate, delegate.isZooming {
            return
        }
        imageNode.image = nil
        image = nil
        text = nil
        imageNode.alpha = 0
        textNode.alpha = 0
        progressNode.isHidden = false
    }

    override func didEnterPreloadState() {
        super.didEnterPreloadState()
        Task {
            await loadPage()
        }
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        displayPage()
    }

    override func animateLayoutTransition(_ context: ASContextTransitioning) {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [
                .transitionCrossDissolve,
                .allowUserInteraction,
                .curveEaseInOut
            ]
        ) {
            if self.image != nil {
                self.imageNode.alpha = 1
            } else if self.text != nil {
                self.textNode.alpha = 1
            } else {
                self.imageNode.alpha = 0
                self.textNode.alpha = 0
            }
        } completion: { [weak self] _ in
            guard let self = self else { return }
            self.imageNode.frame = context.finalFrame(for: self.imageNode)
            self.textNode.frame = context.finalFrame(for: self.textNode)
            if let delegate = self.delegate {
                Task { @MainActor in
                    delegate.scrollView.contentOffset = delegate.collectionNode.contentOffset
                    delegate.zoomView.adjustContentSize()
                }
            }
            context.completeTransition(true)
        }

        // handle inserting cell above
        guard
            let indexPath,
            let collectionNode = owningNode as? ASCollectionNode,
            let layout = collectionNode.collectionViewLayout as? VerticalContentOffsetPreservingLayout,
            let yOffset = collectionNode.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame.origin.y
        else { return }
        layout.isInsertingCellsAbove = yOffset < collectionNode.contentOffset.y
    }

    func getPillarboxHeight(percent: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard let image else { return 0 }
        let width = maxWidth * percent
        return width / image.size.width * image.size.height
    }

    func isPillarboxOrientation() -> Bool {
        pillarboxOrientation == "both" ||
            (pillarboxOrientation == "portrait" && UIDevice.current.orientation.isPortrait) ||
            (pillarboxOrientation == "landscape" && UIDevice.current.orientation.isLandscape)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if let image {
            if pillarbox && isPillarboxOrientation() {
                let percent = (100 - pillarboxAmount) / 100
                let height = getPillarboxHeight(percent: percent, maxWidth: constrainedSize.max.width)

                imageNode.style.width = ASDimensionMakeWithFraction(percent)
                imageNode.style.height = ASDimensionMakeWithPoints(height)
                imageNode.style.alignSelf = .center

                return ASCenterLayoutSpec(
                    horizontalPosition: .center,
                    verticalPosition: .center,
                    sizingOption: [],
                    child: imageNode
                )
            } else {
                return ASRatioLayoutSpec(ratio: image.size.height / image.size.width, child: imageNode)
            }
        } else if text != nil {
            // todo: the text node should probably adjust its size based on the text
            if pillarbox && isPillarboxOrientation() {
                let percent = (100 - pillarboxAmount) / 100
                let ratio = percent * (ratio ?? Self.defaultRatio)

                return ASRatioLayoutSpec(
                    ratio: ratio,
                    child: textNode
                )
            } else {
                return ASRatioLayoutSpec(
                    ratio: ratio ?? Self.defaultRatio,
                    child: textNode
                )
            }
        } else {
            if pillarbox && isPillarboxOrientation() {
                let percent = (100 - pillarboxAmount) / 100
                let ratio = percent * (ratio ?? Self.defaultRatio)

                return ASRatioLayoutSpec(
                    ratio: ratio,
                    child: progressNode
                )
            } else {
                return ASRatioLayoutSpec(
                    ratio: ratio ?? Self.defaultRatio,
                    child: progressNode
                )
            }
        }
    }
}

extension ReaderWebtoonPageNode {

    func loadPage() async {
        guard image == nil, text == nil, !loading else { return }
        loading = true
        imageNode.alpha = 0
        textNode.alpha = 0
        progressNode.isHidden = false
        progressNode.isUserInteractionEnabled = false

        if let image = page.image {
            self.image = image
            if isNodeLoaded {
                displayPage()
            }
            loading = false
        } else if let zipURL = page.zipURL, let url = URL(string: zipURL), let filePath = page.imageURL {
            await loadImage(zipURL: url, filePath: filePath)
        } else if let urlString = page.imageURL, let url = URL(string: urlString) {
            await loadImage(url: url, context: page.context)
        } else if let base64 = page.base64 {
            await loadImage(base64: base64)
        } else if let text = page.text {
             loadText(text)
        } else {
            // TODO: show error
        }
    }

    private func loadImage(url: URL, context: PageContext?) async {
        let urlRequest = if let source {
            await source.getModifiedImageRequest(url: url, context: context)
        } else {
            URLRequest(url: url)
        }

        let shouldDownsample = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let shouldUpscale = UserDefaults.standard.bool(forKey: "Reader.upscaleImages")
        let shouldCropBorders = UserDefaults.standard.bool(forKey: "Reader.cropBorders")
        let width = await UIScreen.main.bounds.width
        var processors: [ImageProcessing] = []
        var usePageProcessor = false
        if
            let source,
            source.features.processesPages,
            !url.isFileURL
        {
            // only process pages if the source supports it and the image isn't downloaded
            processors.append(PageInterceptorProcessor(source: source))
            usePageProcessor = true
        }
        if shouldCropBorders {
            processors.append(CropBordersProcessor())
        }
        if shouldDownsample {
            processors.append(await DownsampleProcessor(width: width))
        } else if shouldUpscale {
            processors.append(UpscaleProcessor())
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.contextKey: context ?? [:], .processesKey: usePageProcessor]
        )

        // Store current image request for reload functionality
        self.currentImageRequest = request

        defer { loading = false }

        let imageTask = ImagePipeline.shared.loadImage(
            with: request,
            progress: { [weak self] _, completed, total in
                guard let self else { return }
                Task { @MainActor in
                    self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
                }
            },
            completion: { _ in }
        )
        do {
            let response = try await imageTask.response
            image = response.image
            if response.container.type == .gif, let data = response.container.data {
                imageNode.animate(withGIFData: data)
            }
            if isNodeLoaded {
                displayPage()
            }
        } catch {
            let error = error as? ImagePipeline.Error
            Task {
                switch error {
                    case .dataLoadingFailed, .dataIsEmpty:
                        // we can still send to image processor even if the request failed
                        if request.userInfo[.processesKey] as? Bool == true {
                            let processor = request.processors.first(where: { $0 is PageInterceptorProcessor }) as? PageInterceptorProcessor
                            if let processor {
                                let result = await Task.detached {
                                    try? processor.processWithoutImage(request: request)
                                }.value
                                if let result {
                                    self.image = result.image
                                    if result.type == .gif, let data = result.data {
                                        self.imageNode.animate(withGIFData: data)
                                    }
                                    if self.isNodeLoaded {
                                        self.displayPage()
                                    }
                                    return
                                }
                            }
                        }
                    default:
                        break
                }

                // TODO: handle failure
                await self.progressView.setProgress(value: 0, withAnimation: true)
            }
        }
    }

    private func loadImage(base64: String) async {
        let request = ImageRequest(
            id: page.key,
            data: { Data() },
            userInfo: [:]
        )

        // Store current image request for reload functionality
        self.currentImageRequest = request

        progressNode.isHidden = false
        defer { loading = false }

        // check cache
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            image = imageContainer?.image
            if isNodeLoaded {
                displayPage()
            }
            return
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
        guard let image else { return }

        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
        self.image = image
        if isNodeLoaded {
            displayPage()
        }
    }

    private func loadImage(zipURL: URL, filePath: String) async {
        var hasher = Hasher()
        hasher.combine(zipURL)
        hasher.combine(filePath)
        let key = String(hasher.finalize())

        let request = ImageRequest(
            id: key,
            data: { Data() },
            userInfo: [:]
        )

        // Store current image request for reload functionality
        self.currentImageRequest = request

        progressNode.isHidden = false
        defer { loading = false }

        // check cache
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            image = imageContainer?.image
            if isNodeLoaded {
                displayPage()
            }
            return
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
                    let processedImage = processor.process(image)
                    if let processedImage = processedImage {
                        image = processedImage
                    }
                }
                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    let processor = await DownsampleProcessor(width: UIScreen.main.bounds.width)
                    let processedImage = processor.process(image)
                    if let processedImage = processedImage {
                        image = processedImage
                    }
                }

                return image
            } catch {
                return nil
            }
        }.value
        guard let image else { return }

        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
        self.image = image
        if isNodeLoaded {
            displayPage()
        }
    }

    private func loadText(_ text: String) {
        self.text = text
        if isNodeLoaded {
            displayPage()
        }
        loading = false
    }

    func displayPage() {
        guard text != nil || image != nil else {
            Task {
                await loadPage()
            }
            return
        }

        if let image {
            progressNode.isHidden = true
            imageNode.image = image

            Task { @MainActor in
                imageNode.isUserInteractionEnabled = true
                if let delegate {
                    imageNode.addInteraction(UIContextMenuInteraction(delegate: delegate))
                }
            }
        } else if let text {
            progressNode.isHidden = true
            textNode.content = MarkdownView(text)
        }

        transition()
    }

    private func transition() {
        let ratio = if let image {
            image.size.width / image.size.height
        } else {
            ratio ?? Self.defaultRatio
        }
        let scaledHeight = UIScreen.main.bounds.width / ratio
        let size = CGSize(width: UIScreen.main.bounds.width, height: scaledHeight)
        frame = CGRect(origin: .zero, size: size)
        transitionLayout(with: ASSizeRange(min: .zero, max: size), animated: true, shouldMeasureAsync: false)
    }

    // MARK: - Image Reload Functionality

    /// Reloads the current image by clearing its cache and re-fetching from the source
    @MainActor
    func reloadCurrentImage() async -> Bool {
        // Clear the cache for the current image
        clearCurrentImageCache()

        // Clear the current image and text to show loading state
        image = nil
        text = nil
        imageNode.image = nil
        imageNode.alpha = 0
        textNode.alpha = 0
        loading = false

        // Reload the image using the original page data
        await loadPage()
        return image != nil || text != nil
    }

    /// Clears the cache entry for the current image
    private func clearCurrentImageCache() {
        // Handle different image types
        if let urlString = page.imageURL, let url = URL(string: urlString) {
            // For URL-based images, remove from both memory and disk cache
            if let currentImageRequest = currentImageRequest {
                ImagePipeline.shared.cache.removeCachedImage(for: currentImageRequest)
            }

            // Also try to remove the basic URL request from cache
            let basicRequest = ImageRequest(url: url)
            ImagePipeline.shared.cache.removeCachedImage(for: basicRequest)

        } else if page.base64 != nil {
            // For base64 images, remove using the page key
            let request = ImageRequest(id: page.key, data: { Data() })
            ImagePipeline.shared.cache.removeCachedImage(for: request)

        } else if let zipURL = page.zipURL, let url = URL(string: zipURL), let filePath = page.imageURL {
            // For zip-based images, remove using the generated key
            var hasher = Hasher()
            hasher.combine(url)
            hasher.combine(filePath)
            let key = String(hasher.finalize())
            let request = ImageRequest(id: key, data: { Data() })
            ImagePipeline.shared.cache.removeCachedImage(for: request)
        }
    }
}
