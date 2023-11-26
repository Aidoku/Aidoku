//
//  ReaderWebtoonImageNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/1/23.
//

import AsyncDisplayKit
import Nuke

class ReaderWebtoonImageNode: BaseObservingCellNode {

    let page: Page

    weak var delegate: ReaderWebtoonViewController?

    var image: UIImage? {
        didSet {
            guard let image else { return }
            ratio = image.size.height / image.size.width
        }
    }
    var ratio: CGFloat?
    private var loading = false

    var pillarbox = UserDefaults.standard.bool(forKey: "Reader.pillarbox")
    var pillarboxAmount = CGFloat(UserDefaults.standard.double(forKey: "Reader.pillarboxAmount"))
    var pillarboxOrientation = UserDefaults.standard.string(forKey: "Reader.pillarboxOrientation")

    static let defaultRatio: CGFloat = 1.435

    var progressView: CircularProgressView {
        (progressNode.view as? CircularProgressView)!
    }

    lazy var imageNode: ASImageNode = {
        let node = ASImageNode()
        node.alpha = 0
        node.contentMode = .scaleToFill
        node.shouldAnimateSizeChanges = false
        node.isUserInteractionEnabled = false
        return node
    }()

    lazy var progressNode: ASCellNode = {
        let tintColor = self.tintColor
        return ASCellNode(viewBlock: {
            CircularProgressView()
        })
    }()

    init(page: Page) {
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
        displayImage()
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
        imageNode.alpha = 0
        progressNode.alpha = 1
    }

    override func didEnterPreloadState() {
        super.didEnterPreloadState()
        Task {
            await loadImage()
        }
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        displayImage()
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
            } else {
                self.imageNode.alpha = 0
            }
        } completion: { [weak self] _ in
            guard let self = self else { return }
            self.imageNode.frame = context.finalFrame(for: self.imageNode)
            if let delegate = self.delegate {
                delegate.scrollView.contentOffset = delegate.collectionNode.contentOffset
                delegate.zoomView.adjustContentSize()
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

extension ReaderWebtoonImageNode {

    func loadImage() async {
        guard image == nil, !loading else { return }
        loading = true
        imageNode.alpha = 0
        progressNode.alpha = 1

        if let urlString = page.imageURL, let url = URL(string: urlString) {
            await loadImage(url: url)
        } else if let base64 = page.base64 {
            loadImage(base64: base64)
        } else {
            // TODO: show error
        }
    }

    private func loadImage(url: URL) async {
        var urlRequest = URLRequest(url: url)

        if
            let source = SourceManager.shared.source(for: page.sourceId),
            source.handlesImageRequests,
            let request = try? await source.getImageRequest(url: url.absoluteString)
        {
            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
        }

        let shouldDownsample = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let shouldCropBorders = UserDefaults.standard.bool(forKey: "Reader.cropBorders")
        let width = await UIScreen.main.bounds.width
        var processors: [ImageProcessing] = []
        if shouldCropBorders {
            processors.append(CropBordersProcessor())
        }
        if shouldDownsample {
            processors.append(DownsampleProcessor(width: width))
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors
        )

        _ = ImagePipeline.shared.loadImage(
            with: request,
            progress: { [weak self] _, completed, total in
                guard let self else { return }
                Task { @MainActor in
                    self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
                }
            },
            completion: { [weak self] result in
                guard let self else { return }
                loading = false
                switch result {
                case .success(let response):
                    image = response.image
                    if isNodeLoaded {
                        displayImage()
                    }
                case .failure:
                    // TODO: handle failure
                    Task { @MainActor in
                        self.progressView.setProgress(value: 0, withAnimation: true)
                    }
                }
            }
        )
    }

    private func loadImage(base64: String) {
        let request = ImageRequest(id: page.key, data: { Data() })

        // TODO: can we show decoding progress?
        progressNode.alpha = 1

        // check cache
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            loading = false
            image = imageContainer?.image
            if isNodeLoaded {
                displayImage()
            }
            return
        }

        // load data and cache
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
                loading = false
                self.image = image
                if isNodeLoaded {
                    displayImage()
                }
            }
        }
    }

    func displayImage() {
        guard let image else {
            Task {
                await loadImage()
            }
            return
        }
        progressNode.alpha = 0
        imageNode.image = image

        transition()

        Task { @MainActor in
            imageNode.isUserInteractionEnabled = true
            if let delegate {
                imageNode.view.addInteraction(UIContextMenuInteraction(delegate: delegate))
            }
        }
    }

    private func transition() {
        guard let image else { return }
        let ratio = image.size.width / image.size.height
        let scaledHeight = UIScreen.main.bounds.width / ratio
        let size = CGSize(width: UIScreen.main.bounds.width, height: scaledHeight)
        frame = CGRect(origin: .zero, size: size)
        transitionLayout(with: ASSizeRange(min: .zero, max: size), animated: true, shouldMeasureAsync: false)
    }
}
