//
//  ReaderPageCollectionViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/9/22.
//

import UIKit
import Nuke

class ReaderPageCollectionViewCell: UICollectionViewCell {

    var sourceId: String?

    var pageView: ReaderScrollPageView?
    var infoView: ReaderInfoPageView?

    func convertToPage() {
        guard pageView == nil else { return }

        infoView?.removeFromSuperview()
        infoView = nil

        pageView = ReaderScrollPageView(sourceId: sourceId ?? "")
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
        // check Nuke cache first
        let request = ImageRequest(url: URL(string: "https://" + page.key))
        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            if let image = ImagePipeline.shared.cache.cachedImage(for: request) {
                self.pageView?.setPageImage(image: image.image, key: page.key)
                return
            }
        }

        if let url = page.imageURL {
            setPageImage(url: url, key: page.key)
        } else if let base64 = page.base64 {
            setPageImage(base64: base64, key: page.key)
        } else if let text = page.text {
            setPageText(text: text)
        }
    }

    func setPage(cacheKey: String) {
        if let image = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: URL(string: "https://" + cacheKey))) {
            self.pageView?.imageView.image = image.image
        }
    }

    func setPageImage(url: String, key: String) {
        guard pageView?.currentUrl ?? "" != url || pageView?.imageView.image == nil else { return }
        Task {
            await pageView?.setPageImage(url: url, key: key)
        }
    }

    func setPageImage(base64: String, key: String) {
        pageView?.setPageImage(base64: base64, key: key)
    }

    func setPageData(data: Data, key: String? = nil) {
        pageView?.setPageData(data: data, key: key)
    }

    func setPageText(text: String) {
        pageView?.setPageText(text: text)
    }
}
