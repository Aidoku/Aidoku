//
//  ReaderPageCollectionViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/9/22.
//

import UIKit
import Kingfisher

class ReaderPageCollectionViewCell: UICollectionViewCell {

    var sourceId: String?

    var pageView: ReaderPageView?
    var infoView: ReaderInfoPageView?

    func convertToPage() {
        guard pageView == nil else { return }

        infoView?.removeFromSuperview()
        infoView = nil

        pageView = ReaderPageView(sourceId: sourceId ?? "", mode: .scroll)
        pageView?.zoomEnabled = false
        pageView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView!)

        pageView?.topAnchor.constraint(equalTo: topAnchor).isActive = true
        pageView?.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        pageView?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        pageView?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func convertToInfo(type: ReaderInfoPageType, currentChapter: Chapter) {
        guard infoView == nil else { return }

        pageView?.removeFromSuperview()
        pageView = nil

        infoView = ReaderInfoPageView(type: type, currentChapter: currentChapter)
        infoView?.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoView!)

        infoView?.topAnchor.constraint(equalTo: topAnchor).isActive = true
        infoView?.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        infoView?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        infoView?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    func setPage(page: Page) {
        if let url = page.imageURL {
            setPageImage(url: url, key: page.key)
        } else if let base64 = page.base64 {
            setPageImage(base64: base64, key: page.key)
        } else if let text = page.text {
            setPageText(text: text)
        }
    }

    func setPage(cacheKey: String) {
        KingfisherManager.shared.cache.retrieveImage(forKey: cacheKey) { result in
            switch result {
            case .success(let value):
                self.pageView?.imageView.image = value.image
            default:
                break
            }
        }
    }

    func setPageImage(url: String, key: String) {
        guard pageView?.currentUrls[0] ?? "" != url || (pageView?.multiView.subviews[0] as? UIImageView)?.image == nil else { return }
        pageView?.setPageImage(url: url, key: key, page: 0)
    }

    func setPageImage(base64: String, key: String) {
        pageView?.setPageImage(base64: base64, key: key, page: 0)
    }

    func setPageData(data: Data, key: String? = nil) {
        pageView?.setPageData(data: data, key: key, page: 0)
    }

    func setPageText(text: String) {
        pageView?.setPageText(text: text)
    }
}
