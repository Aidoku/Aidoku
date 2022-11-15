//
//  ReaderWebtoonCollectionViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit

class ReaderWebtoonCollectionViewCell: UICollectionViewCell {

    static let estimatedHeight: CGFloat = 300

    let pageView = ReaderPageView2()
    var page: Page?

    var infoPageType: ReaderPageViewController.InfoPageType?
    var infoView: ReaderInfoPageView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        pageView.maxWidth = true
        pageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView)

        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: topAnchor),
            pageView.widthAnchor.constraint(equalTo: widthAnchor),
            pageView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.estimatedHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPage(page: Page) {
        self.page = page
    }

    func loadPage(sourceId: String? = nil) async {
        guard let page = page, page.type == .imagePage else { return }
        infoView?.isHidden = true
        pageView.isHidden = false
        _ = await pageView.setPage(page, sourceId: sourceId)
    }

    func loadInfo(prevChapter: Chapter?, nextChapter: Chapter?) {
        guard let page = page, page.type != .imagePage else { return }
        if infoView == nil {
            let infoView = ReaderInfoPageView(type: page.type == .prevInfoPage ? .previous : .next)
            infoView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(infoView)
            NSLayoutConstraint.activate([
                infoView.topAnchor.constraint(equalTo: topAnchor),
                infoView.leftAnchor.constraint(equalTo: leftAnchor),
                infoView.rightAnchor.constraint(equalTo: rightAnchor),
                infoView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            self.infoView = infoView
        } else if (page.type == .prevInfoPage && infoView?.type != .previous) || (page.type == .nextInfoPage && infoView?.type != .next) {
            infoView?.type = page.type == .prevInfoPage ? .previous : .next
        }
        infoView?.isHidden = false
        pageView.isHidden = true
        if page.type == .prevInfoPage {
            infoView?.previousChapter = prevChapter
            infoView?.currentChapter = nextChapter
            infoView?.nextChapter = nil
        } else {
            infoView?.previousChapter = nil
            infoView?.currentChapter = prevChapter
            infoView?.nextChapter = nextChapter
        }
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        // estimate height of 300
        let fallback = CGSize(width: bounds.width != 0 ? bounds.width : UIScreen.main.bounds.width, height: Self.estimatedHeight)

        if page?.type != .imagePage {
            layoutAttributes.size = fallback
        } else {
            let size = pageView.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
            if size.height > 0 {
                layoutAttributes.size = size
            } else {
                layoutAttributes.size = fallback
            }
        }

        return layoutAttributes
    }
}
