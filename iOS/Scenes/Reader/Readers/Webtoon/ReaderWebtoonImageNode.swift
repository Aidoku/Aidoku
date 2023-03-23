//
//  ReaderWebtoonImageNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/1/23.
//

import AsyncDisplayKit
import Nuke

class ReaderWebtoonImageNode: ASCellNode {

    let page: Page

    weak var delegate: ReaderWebtoonViewController?

    var image: UIImage?
    private var imageTask: ImageTask?
    private var loading = false

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
    }

    override func didEnterDisplayState() {
        super.didEnterDisplayState()
        displayImage()
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

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if let image {
            // TODO: pillarboxing
            return ASRatioLayoutSpec(ratio: image.size.height / image.size.width, child: imageNode)
        } else {
            return ASRatioLayoutSpec(
                ratio: Self.defaultRatio,
                child: progressNode
            )
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

        let shouldDownscale = UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
        let width = await UIScreen.main.bounds.width
        let processors = shouldDownscale ? [DownsampleProcessor(width: width)] : []

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: processors
        )

        _ = try? await ImagePipeline.shared.image(for: request, delegate: self)
    }

    private func loadImage(base64: String) {
        let request = ImageRequest(id: page.key, data: { Data() })

        // TODO: can we show decoding progress?
        progressNode.alpha = 1

        // check cache
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            image = imageContainer?.image
            progressNode.alpha = 0
            if isNodeLoaded {
                displayImage()
            }
            return
        }

        // load data and cache
        if let data = Data(base64Encoded: base64) {
            if var image = UIImage(data: data) {
                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    let processor = DownsampleProcessor(width: UIScreen.main.bounds.width)
                    let processedImage = processor.process(image)
                    if let processedImage = processedImage {
                        image = processedImage
                    }
                }
                ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
                self.image = image
                progressNode.alpha = 0
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
        imageNode.shouldAnimateSizeChanges = false

        let ratio = image.size.width / image.size.height
        let scaledHeight = UIScreen.main.bounds.width / ratio
        let size = CGSize(width: UIScreen.main.bounds.width, height: scaledHeight)
        frame = .init(origin: .zero, size: size)

        transitionLayout(with: .init(min: .zero, max: size), animated: true, shouldMeasureAsync: false)

        Task { @MainActor in
            imageNode.isUserInteractionEnabled = true
            if let delegate {
                imageNode.view.addInteraction(UIContextMenuInteraction(delegate: delegate))
            }
        }
    }
}

// MARK: - Nuke Delegate
extension ReaderWebtoonImageNode: ImageTaskDelegate {

    func imageTaskCreated(_ task: ImageTask) {
        imageTask = task
    }

    func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>) {
        loading = false
        switch result {
        case .success(let response):
            image = response.image
            if isNodeLoaded {
                displayImage()
            }
        case .failure:
            // TODO: handle failure
            break
        }
        progressNode.alpha = 0
    }

    func imageTaskDidCancel(_ task: ImageTask) {
        // TODO: handle failure
    }

    func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
        progressView.setProgress(value: Float(progress.completed) / Float(progress.total), withAnimation: false)
    }
}
