//
//  ReaderTextViewController.swift
//  Aidoku
//
//  Created by Skitty on 5/13/25.
//

import AidokuRunner
import SwiftUI

class ReaderTextViewController: BaseViewController {
    let viewModel: ReaderTextViewModel

    var readingMode: ReadingMode = .rtl
    var delegate: (any ReaderHoldingDelegate)?

    private var isSliding = false

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .systemBackground
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        return scrollView
    }()
    private lazy var hostingController: UIHostingController<ReaderTextView> = {
        let hostingController = HostingController(
            rootView: ReaderTextView(source: viewModel.source, page: viewModel.pages.first)
        )
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = .intrinsicContentSize
        }
        hostingController.view.backgroundColor = .clear
        return hostingController
    }()

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.viewModel = .init(source: source, manga: manga)
        super.init()
    }

    override func configure() {
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        scrollView.addSubview(hostingController.view)

        view.addSubview(scrollView)
    }

    override func constrain() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

//            hostingController.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
//            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
//            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
//            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)

            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            // Fix the width to prevent horizontal scrolling
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        hostingController.view.invalidateIntrinsicContentSize()
        scrollView.contentSize = hostingController.view.intrinsicContentSize
    }
}

// MARK: - Reader Delegate
extension ReaderTextViewController: ReaderReaderDelegate {
    func moveLeft() {
        let offset = CGPoint(
            x: scrollView.contentOffset.x,
            y: max(
                0,
                scrollView.contentOffset.y - scrollView.bounds.height * 2/3
            )
        )
        scrollView.setContentOffset(
            offset,
            animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
        )
    }

    func moveRight() {
        let offset = CGPoint(
            x: scrollView.contentOffset.x,
            y: min(
                scrollView.contentSize.height - scrollView.bounds.height,
                scrollView.contentOffset.y + scrollView.bounds.height * 2/3
            )
        )
        scrollView.setContentOffset(
            offset,
            animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")
        )
    }

    func sliderMoved(value: CGFloat) {
        isSliding = true

        let totalHeight = scrollView.contentSize.height - scrollView.frame.size.height
        let offset = totalHeight * value

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: offset),
            animated: false
        )
    }

    func sliderStopped(value: CGFloat) {
        isSliding = false
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        guard chapter != viewModel.chapter else { return }

        Task {
            await viewModel.loadPages(chapter: chapter)
            delegate?.setPages(viewModel.pages)

            // update text
            if let firstPage = viewModel.pages.first {
                hostingController.rootView = ReaderTextView(source: viewModel.source, page: firstPage)
            }

            // scroll to top
            scrollView.setContentOffset(.init(x: 0, y: 0), animated: false)
        }
    }
}

// MARK: - Scroll View Delegate
extension ReaderTextViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSliding else { return }

        let totalHeight = scrollView.contentSize.height - scrollView.frame.size.height
        let offset = min(1, max(0, scrollView.contentOffset.y / totalHeight))
        delegate?.setSliderOffset(offset)
    }
}

// MARK: - ReaderTextView
private struct ReaderTextView: View {
    let source: AidokuRunner.Source?
    let page: Page?

    var body: some View {
        if let page {
            if let text = page.text {
                MarkdownView(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
