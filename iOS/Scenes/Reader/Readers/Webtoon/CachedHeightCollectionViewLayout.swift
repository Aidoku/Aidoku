//
//  CachedHeightCollectionViewLayout.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 10/15/22.
//

import UIKit

// it would be great if I could this this to work as intended, but the issue with it is that
// content size adjustments for when a cell changes height causes scrolling to become stuttery.
// this doesn't happen when I use the collection view data sources's reconfigureItems method (ios 15+).

class CachedHeightCollectionViewLayout: UICollectionViewFlowLayout {

    var cachedHeights: [IndexPath: CGFloat] = [:]

    private var currentAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    private var contentSize = CGSize.zero
    override var collectionViewContentSize: CGSize {
        contentSize
    }

    private var estimatedHeight: CGFloat = ReaderWebtoonCollectionViewCell.estimatedHeight
    private var scale: CGFloat = 1

    override init() {
        super.init()
        minimumInteritemSpacing = 0
        minimumLineSpacing = 0
        sectionInset = .zero
        // setting estimated item size disables cell prefetching
        // estimatedItemSize = CGSize(width: UIScreen.main.bounds.size.width, height: estimatedHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView, collectionView.numberOfSections > 0 else { return }

        currentAttributes = [:]

        var origin: CGFloat = 0
        let width = collectionView.bounds.size.width

        for section in 0..<collectionView.numberOfSections {
            for itemIndex in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: itemIndex, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)

                let size = CGSize(width: width, height: cachedHeights[indexPath] ?? estimatedHeight)
                if size.height > estimatedHeight {
                    estimatedHeight = size.height
                }
                attributes.frame = CGRect(origin: CGPoint(x: 0, y: origin), size: size)
                currentAttributes[indexPath] = attributes

                origin += size.height
            }
        }

        let size = CGSize(width: width, height: origin)

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        contentSize = size.applying(transform)

        // adjust cells for zoom
        for section in 0..<collectionView.numberOfSections {
            for itemIndex in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: itemIndex, section: section)
                if let origFrame = currentAttributes[indexPath]?.frame {
                    let frame = CGRect(
                        origin: CGPoint(
                            x: origFrame.origin.x / size.width * contentSize.width,
                            y: origFrame.origin.y / origin * contentSize.height
                        ),
                        size: origFrame.size.applying(transform)
                    )
                    // setting frame without transform doesn't scale content,
                    // and setting frame with transform messes up the scale
                    currentAttributes[indexPath]?.transform = transform
                    currentAttributes[indexPath]?.center = CGPoint(
                        x: frame.origin.x + frame.width / 2,
                        y: frame.origin.y + frame.height / 2
                    )
                }
            }
        }
    }

    func getHeightFor(section: Int, range: Range<Int>) -> CGFloat {
        var height: CGFloat = 0
        for idx in range {
            let indexPath = IndexPath(item: idx, section: section)
            let attributes = currentAttributes[indexPath]
            height += attributes?.frame.height ?? 0
        }
        return height * scale
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        currentAttributes[indexPath]
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributes: [UICollectionViewLayoutAttributes] = []
        for item in currentAttributes where rect.intersects(item.value.frame) {
            attributes.append(item.value)
        }
        return attributes
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool {
//        if let height = cachedHeights[preferredAttributes.indexPath] {
//            return originalAttributes.size.height != height
//        }
//        return preferredAttributes.size.height != originalAttributes.size.height
        false
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let invalidationContext = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes
        )

        let oldHeight = originalAttributes.size.height
        let cachedHeight = cachedHeights[preferredAttributes.indexPath]
        let newHeight = cachedHeight ?? preferredAttributes.size.height
        if cachedHeight == nil {
            cachedHeights[preferredAttributes.indexPath] = newHeight
        }

        let oldAdjustment = invalidationContext.contentSizeAdjustment

        invalidationContext.contentSizeAdjustment = CGSize(
            width: oldAdjustment.width,
            height: oldAdjustment.height + newHeight - oldHeight
        )

        return invalidationContext
    }
}

// MARK: - Zoom Support
extension CachedHeightCollectionViewLayout: ZoomableLayoutProtocol {

    func getScale() -> CGFloat {
        scale
    }

    func setScale(_ scale: CGFloat) {
        self.scale = scale
    }
}
