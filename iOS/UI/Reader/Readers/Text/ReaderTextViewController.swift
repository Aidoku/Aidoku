//
//  ReaderTextViewController.swift
//  Aidoku
//
//  Created by Skitty on 5/13/25.
//

import AidokuRunner
import SwiftUI
import ZIPFoundation

class ReaderTextViewController: BaseViewController {
    let viewModel: ReaderTextViewModel

    var readingMode: ReadingMode = .rtl
    var delegate: (any ReaderHoldingDelegate)?

    // Chapter navigation
    private var previousChapter: AidokuRunner.Chapter?
    private var nextChapter: AidokuRunner.Chapter?
    private var isLoadingChapter = false
    private var hasReachedEnd = false

    private var isSliding = false

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .systemBackground
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        return scrollView
    }()

    private lazy var contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        return sv
    }()

    private var hostingController: UIHostingController<ReaderTextView>?

    private func createHostingController(page: Page?) -> UIHostingController<ReaderTextView> {
        let hc = HostingController(
            rootView: ReaderTextView(source: viewModel.source, page: page)
        )
        if #available(iOS 16.0, *) {
            hc.sizingOptions = .intrinsicContentSize
        }
        hc.view.backgroundColor = .clear
        return hc
    }

    // Footer view for chapter navigation
    private lazy var footerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        return view
    }()

    private lazy var footerStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 16
        return sv
    }()

    private lazy var footerTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var footerChapterLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var nextChapterButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = NSLocalizedString("CONTINUE_READING")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(nextChapterTapped), for: .touchUpInside)
        return button
    }()

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.viewModel = .init(source: source, manga: manga)
        super.init()
    }

    override func configure() {
        // Create initial hosting controller
        let hc = createHostingController(page: viewModel.pages.first)
        hostingController = hc
        addChild(hc)
        hc.didMove(toParent: self)

        // Build content stack
        contentStackView.addArrangedSubview(hc.view)
        contentStackView.addArrangedSubview(footerView)

        // Footer content
        footerView.addSubview(footerStackView)
        footerStackView.addArrangedSubview(footerTitleLabel)
        footerStackView.addArrangedSubview(footerChapterLabel)
        footerStackView.addArrangedSubview(nextChapterButton)

        scrollView.addSubview(contentStackView)
        view.addSubview(scrollView)

        // Initially hide footer
        footerView.isHidden = true
    }

    override func constrain() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        hostingController?.view.translatesAutoresizingMaskIntoConstraints = false
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            // Fix the width to prevent horizontal scrolling
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Footer layout
            footerView.heightAnchor.constraint(equalToConstant: 200),
            footerStackView.centerXAnchor.constraint(equalTo: footerView.centerXAnchor),
            footerStackView.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            footerStackView.leadingAnchor.constraint(greaterThanOrEqualTo: footerView.leadingAnchor, constant: 32),
            footerStackView.trailingAnchor.constraint(lessThanOrEqualTo: footerView.trailingAnchor, constant: -32)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        hostingController?.view.invalidateIntrinsicContentSize()
    }

    private func updateFooter() {
        if let nextChapter {
            footerView.isHidden = false
            footerTitleLabel.text = NSLocalizedString("NEXT_CHAPTER")

            if let chapterNum = nextChapter.chapterNumber {
                footerChapterLabel.text = String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            } else {
                footerChapterLabel.text = nextChapter.title ?? ""
            }

            nextChapterButton.isHidden = false
        } else {
            footerView.isHidden = false
            footerTitleLabel.text = NSLocalizedString("NO_NEXT_CHAPTER")
            footerChapterLabel.text = NSLocalizedString("END_OF_MANGA")
            nextChapterButton.isHidden = true
        }
    }

    @objc private func nextChapterTapped() {
        loadNextChapter()
    }

    func loadNextChapter() {
        guard let nextChapter, !isLoadingChapter else { return }
        delegate?.setChapter(nextChapter)
        Task {
            await loadChapter(nextChapter)
        }
    }

    func loadPreviousChapter() {
        guard let previousChapter, !isLoadingChapter else { return }
        delegate?.setChapter(previousChapter)
        Task {
            await loadChapter(previousChapter)
        }
    }

    private func loadChapter(_ chapter: AidokuRunner.Chapter) async {
        isLoadingChapter = true
        hasReachedEnd = false

        await viewModel.loadPages(chapter: chapter)
        delegate?.setPages(viewModel.pages)

        await MainActor.run {
            previousChapter = delegate?.getPreviousChapter()
            nextChapter = delegate?.getNextChapter()

            // Update text - recreate hosting controller to force full refresh
            if let firstPage = viewModel.pages.first {
                // Remove old view
                hostingController?.view.removeFromSuperview()
                hostingController?.removeFromParent()

                // Create new hosting controller with new content
                let newHostingController = createHostingController(page: firstPage)

                // Add to view hierarchy
                addChild(newHostingController)
                newHostingController.didMove(toParent: self)

                // Insert at the beginning of the stack view
                contentStackView.insertArrangedSubview(newHostingController.view, at: 0)
                newHostingController.view.translatesAutoresizingMaskIntoConstraints = false

                // Update reference
                hostingController = newHostingController
            }

            // Update footer
            updateFooter()

            // Force scroll view to recalculate content size
            view.layoutIfNeeded()

            // Scroll to top
            scrollView.setContentOffset(.init(x: 0, y: 0), animated: false)

            isLoadingChapter = false
        }
    }
}

// MARK: - Reader Delegate
extension ReaderTextViewController: ReaderReaderDelegate {
    func moveLeft() {
        // At the top? Try previous chapter
        if scrollView.contentOffset.y <= 0 {
            loadPreviousChapter()
            return
        }

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
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height

        // At the bottom? Try next chapter
        if scrollView.contentOffset.y >= maxOffset - 10 {
            loadNextChapter()
            return
        }

        let offset = CGPoint(
            x: scrollView.contentOffset.x,
            y: min(
                maxOffset,
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
            await loadChapter(chapter)
        }
    }
}

// MARK: - Scroll View Delegate
extension ReaderTextViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSliding else { return }

        let totalHeight = scrollView.contentSize.height - scrollView.frame.size.height
        guard totalHeight > 0 else { return }

        let offset = min(1, max(0, scrollView.contentOffset.y / totalHeight))
        delegate?.setSliderOffset(offset)

        // Mark as completed when reaching the end (within 50pt of bottom)
        if scrollView.contentOffset.y >= totalHeight - 50 && !hasReachedEnd {
            hasReachedEnd = true
            delegate?.setCompleted()
        }
    }
}

// MARK: - ReaderTextView
private struct ReaderTextView: View {
    let source: AidokuRunner.Source?
    let text: String?

    private var fontFamily: String {
        UserDefaults.standard.string(forKey: "Reader.textFontFamily") ?? "Georgia"
    }
    private var fontSize: Double {
        UserDefaults.standard.object(forKey: "Reader.textFontSize") as? Double ?? 16
    }
    private var lineSpacing: Double {
        UserDefaults.standard.object(forKey: "Reader.textLineSpacing") as? Double ?? 6
    }

    init(source: AidokuRunner.Source?, page: Page?) {
        self.source = source

        func loadText(page: Page) -> String? {
            if let text = page.text {
                return text
            }

            guard
                let zipURL = page.zipURL.flatMap({ URL(string: $0) }),
                let filePath = page.imageURL
            else {
                return nil
            }
            do {
                var data = Data()
                let archive = try Archive(url: zipURL, accessMode: .read)
                guard let entry = archive[filePath] else {
                    return nil
                }
                _ = try archive.extract(
                    entry,
                    consumer: { readData in
                        data.append(readData)
                    }
                )
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }
        self.text = page.flatMap { loadText(page: $0) }
    }

    var body: some View {
        if let text {
            MarkdownView(text, fontFamily: fontFamily, fontSize: fontSize, lineSpacing: lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
