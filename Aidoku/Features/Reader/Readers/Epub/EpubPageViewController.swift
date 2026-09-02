//
//  EpubPageViewController.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/28/26.
//

import UIKit
import WebKit

// one visual page of the book, the unit UIPageViewController turns. it displays a web view leased
// from the paged reader's roster rather than owning one: a loaded spine document is a whole web
// content process, and a book's worth of pages cannot each hold one
@MainActor
final class EpubPageViewController: UIViewController {
    let bookPage: Int
    let document: Int
    let pageInDocument: Int

    private(set) weak var webView: WKWebView?

    // the web view shows the whole spine document scrolled to this page, so its touches must never
    // reach WebKit: the text reader's pages are inert the same way, which is what lets the page
    // controller's own pan recognise over them
    private let insets: UIEdgeInsets

    var isDisplaying: Bool {
        guard let webView else { return false }
        return webView.superview === view
    }

    init(bookPage: Int, document: Int, pageInDocument: Int, insets: UIEdgeInsets) {
        self.bookPage = bookPage
        self.document = document
        self.pageInDocument = pageInDocument
        self.insets = insets
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // opaque, so the instant before a leased web view arrives reads as a blank page rather
        // than a hole in the book
        view.backgroundColor = .systemBackground
    }

    // the web view already holds this page's document at this page's offset
    func display(_ webView: WKWebView) {
        if let current = self.webView, current !== webView, current.superview === view {
            current.removeFromSuperview()
        }
        self.webView = webView
        webView.isUserInteractionEnabled = false
        guard webView.superview !== view else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        loadViewIfNeeded()
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: insets.right),
            view.bottomAnchor.constraint(equalTo: webView.bottomAnchor, constant: insets.bottom)
        ])
        view.layoutIfNeeded()
    }

    // the page keeps its identity and is provisioned again if turned to
    func surrender() -> WKWebView? {
        guard let webView, webView.superview === view else {
            self.webView = nil
            return nil
        }
        webView.removeFromSuperview()
        self.webView = nil
        return webView
    }
}
