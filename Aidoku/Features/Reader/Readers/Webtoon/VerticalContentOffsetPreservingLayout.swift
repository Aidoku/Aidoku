//
//  VerticalContentOffsetPreservingLayout.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/1/23.
//  Thanks to Mantton (https://github.com/Mantton) for this.
//

import UIKit
import AsyncDisplayKit

class VerticalContentOffsetPreservingLayout: UICollectionViewFlowLayout {

    var isInsertingCellsAbove: Bool = false {
        didSet {
            if isInsertingCellsAbove {
                contentSizeBeforeInsertingAbove = collectionViewContentSize
            }
        }
    }

    var spacing: CGFloat {
        get { minimumLineSpacing }
        set { minimumLineSpacing = newValue }
    }

    private var contentSizeBeforeInsertingAbove: CGSize?
    private var scale: CGFloat = 1

    private var contentSize = CGSize.zero
    override var collectionViewContentSize: CGSize {
        contentSize
    }

    private var currentAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    private struct ViewportAnchor {
        let indexPath: IndexPath
        let position: CGPoint
    }

    private var preservedViewportAnchor: ViewportAnchor?

    func preserveVisiblePosition() {
        guard let collectionView else { return }

        let bounds = collectionView.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard
            let attributes = layoutAttributesForElements(in: bounds)?
                .filter({ $0.representedElementCategory == .cell && $0.frame.width > 0 && $0.frame.height > 0 })
                .min(by: {
                    let first = max($0.frame.minY - center.y, center.y - $0.frame.maxY, 0)
                    let second = max($1.frame.minY - center.y, center.y - $1.frame.maxY, 0)
                    return first < second
                })
        else {
            preservedViewportAnchor = nil
            return
        }

        preservedViewportAnchor = ViewportAnchor(
            indexPath: attributes.indexPath,
            position: CGPoint(
                x: (center.x - attributes.frame.minX) / attributes.frame.width,
                y: (center.y - attributes.frame.minY) / attributes.frame.height
            )
        )
    }

    func clearPreservedPosition() {
        preservedViewportAnchor = nil
    }

    override init() {
        super.init()
        scrollDirection = .vertical
        minimumInteritemSpacing = 0
        minimumLineSpacing = 0
        sectionInset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepare() {
        guard let collectionView else { return }

        // calculate collection view size
        currentAttributes = [:]

        var origin: CGFloat = 0
        let width = collectionView.bounds.size.width

        for section in 0..<collectionView.numberOfSections {
            for itemIndex in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: itemIndex, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)

                let size = CGSize(width: width, height: getHeight(for: indexPath))
                attributes.frame = CGRect(origin: CGPoint(x: 0, y: origin), size: size)
                currentAttributes[indexPath] = attributes

                origin += attributes.frame.size.height + minimumLineSpacing
            }
        }

        // scale for zoom
        let size = CGSize(width: width, height: origin)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        contentSize = size.applying(transform)

        if scale != 1 {
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

        // preserve offset when inserting cells above
        if isInsertingCellsAbove {
            if let oldContentSize = contentSizeBeforeInsertingAbove {
                UIView.performWithoutAnimation {
                    let newContentSize = collectionViewContentSize
                    let contentOffsetX = collectionView.contentOffset.x + (newContentSize.width - oldContentSize.width)
                    let contentOffsetY = collectionView.contentOffset.y + (newContentSize.height - oldContentSize.height)
                    let newOffset = CGPoint(x: contentOffsetX, y: contentOffsetY)
                    collectionView.contentOffset = newOffset
                }
            }
            contentSizeBeforeInsertingAbove = nil
            isInsertingCellsAbove = false
        }
    }

    func getHeight(for indexPath: IndexPath) -> CGFloat {
        guard
            let collectionView = collectionView as? ASCollectionView,
            let collectionNode = collectionView.collectionNode,
            let node = collectionNode.nodeForItem(at: indexPath) as? HeightQueryable
        else {
            return 0
        }
        return node.getHeight(for: collectionView.bounds.size)
    }

    func getHeightFor(section: Int, range: Range<Int>? = nil) -> CGFloat {
        var height: CGFloat = 0
        let range = range ?? 0..<(collectionView?.numberOfItems(inSection: section) ?? 0)
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

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard
            let collectionView,
            let anchor = preservedViewportAnchor,
            let attributes = layoutAttributesForItem(at: anchor.indexPath)
        else {
            return proposedContentOffset
        }

        let frame = attributes.frame
        let size = collectionView.bounds.size
        let inset = collectionView.adjustedContentInset
        let minimum = CGPoint(x: -inset.left, y: -inset.top)
        let maximum = CGPoint(
            x: max(minimum.x, collectionViewContentSize.width - size.width + inset.right),
            y: max(minimum.y, collectionViewContentSize.height - size.height + inset.bottom)
        )

        return CGPoint(
            x: min(max(frame.minX + frame.width * anchor.position.x - size.width / 2, minimum.x), maximum.x),
            y: min(max(frame.minY + frame.height * anchor.position.y - size.height / 2, minimum.y), maximum.y)
        )
    }
}

// MARK: - Zoom Support
extension VerticalContentOffsetPreservingLayout: @MainActor ZoomableLayoutProtocol {
    func getScale() -> CGFloat {
        scale
    }

    func setScale(_ scale: CGFloat) {
        self.scale = scale
    }
}
