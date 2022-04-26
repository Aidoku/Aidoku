//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//

import UIKit
import Kingfisher

extension Bool {
    var intValue: Int {
        self ? 1 : 0
    }
}

extension UINavigationItem {
    func setTitle(upper: String?, lower: String) {
        if let upper = upper {
            let upperLabel = UILabel()
            upperLabel.text = upper
            upperLabel.font = UIFont.systemFont(ofSize: 11)
            upperLabel.textColor = .secondaryLabel

            let lowerLabel = UILabel()
            lowerLabel.text = lower
            lowerLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            lowerLabel.textAlignment = .center

            let stackView = UIStackView(arrangedSubviews: [upperLabel, lowerLabel])
            stackView.distribution = .equalCentering
            stackView.axis = .vertical
            stackView.alignment = .center

            let width = max(upperLabel.frame.size.width, lowerLabel.frame.size.width)
            stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)

            upperLabel.sizeToFit()
            lowerLabel.sizeToFit()

            self.titleView = stackView
        } else {
            self.titleView = nil
            self.title = lower
        }
    }
}

extension UIToolbar {
    var contentView: UIView? {
        subviews.first { view in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ContentView")
        }
    }

    var stackView: UIView? {
        contentView?.subviews.first { view -> Bool in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ButtonBarStackView")
        }
    }

   func fitContentViewToToolbar() {
        guard let stackView = stackView, let contentView = contentView else { return }
        stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        stackView.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
    }
}

class ReaderViewController: UIViewController {

    let manga: Manga?
    var chapter: Chapter
    var chapterList: [Chapter]

    var readingMode: MangaViewer = .defaultViewer

    var chapterIndex: Int {
        chapterList.firstIndex(of: chapter) ?? 0
    }

    var ignoreSet = false

    var items: [UIViewController] = []
    var pageManager: ReaderPageManager! {
        willSet {
            guard pageManager != nil, !ignoreSet else { return }
            pageManager.remove()
        }
        didSet {
            if ignoreSet {
                ignoreSet = false
                return
            }

            pageManager.delegate = self
            pageManager.readingMode = readingMode
            pageManager.attach(toParent: self)

            pageManager.setChapter(chapter: chapter, startPage: DataManager.shared.currentPage(for: chapter))
        }
    }

    lazy var singleTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
        tap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)

        return tap
    }()

    let transitionView = UIView()

    let toolbarView = ToolbarContainerView()
    let sliderView = ReaderSliderView()
    let currentPageLabel = UILabel()
    let pagesLeftLabel = UILabel()
    let progressView = UIActivityIndicatorView(style: .medium)

    var toolbarSliderWidthConstraint: NSLayoutConstraint?

    var currentPageIndex = 0

    var statusBarHidden = false

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }

    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(manga: Manga?, chapter: Chapter, chapterList: [Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.chapterList = chapterList
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        modalPresentationCapturesStatusBarAppearance = true

        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(openChapterSelectionPopover(_:))
            )
        ]

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: nil,
                action: nil
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings(_:))
            )
        ]
        navigationItem.rightBarButtonItems?.first?.isEnabled = false

        navigationController?.navigationBar.prefersLargeTitles = false

        // Fixes navbar being clear
        let navigationBarAppearance = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        toolbarAppearance.configureWithDefaultBackground()
        navigationController?.navigationBar.standardAppearance = navigationBarAppearance
        navigationController?.navigationBar.compactAppearance = navigationBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navigationBarAppearance
        navigationController?.toolbar.standardAppearance = toolbarAppearance
        navigationController?.toolbar.compactAppearance = toolbarAppearance
        if #available(iOS 15.0, *) {
            navigationController?.toolbar.scrollEdgeAppearance = toolbarAppearance
        }

        currentPageLabel.font = .systemFont(ofSize: 10)
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(currentPageLabel)

        pagesLeftLabel.font = .systemFont(ofSize: 10)
        pagesLeftLabel.textColor = .secondaryLabel
        pagesLeftLabel.textAlignment = .right
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(pagesLeftLabel)

        sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        sliderView.addTarget(self, action: #selector(sliderDone(_:)), for: .editingDidEnd)
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(sliderView)

        toolbarView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 24)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false

        let toolbarSlider = UIBarButtonItem(customView: toolbarView)
        toolbarSliderWidthConstraint = toolbarSlider.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
        toolbarSlider.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        toolbarSlider.customView?.transform = CGAffineTransform(translationX: 0, y: -10)

        navigationController?.isToolbarHidden = false
        toolbarItems = [toolbarSlider]

        navigationController?.toolbar.fitContentViewToToolbar()

        // Shows when orientation changing in order to cover up the jerky scrolling happening
        transitionView.isHidden = true
        transitionView.backgroundColor = .black
        transitionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transitionView)

        // TODO: Make this an indefinite progress view more like the circular progress view
        progressView.center = view.center
        progressView.hidesWhenStopped = true
        progressView.startAnimating()
        view.addSubview(progressView)

        view.addGestureRecognizer(singleTap)

        activateConstraints()

        setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode"))

        NotificationCenter.default.addObserver(forName: NSNotification.Name("Reader.readingMode"), object: nil, queue: nil) { _ in
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode"))
        }

        Task {
            await loadChapter()
        }
    }

    func setReadingMode(_ mode: String?) {
        switch mode {
        case "rtl": readingMode = .rtl
        case "ltr": readingMode = .ltr
        case "vertical": readingMode = .vertical
        case "scroll": readingMode = .scroll
        default:
            if let manga = manga {
                readingMode = manga.viewer
            } else {
                readingMode = .defaultViewer
            }
        }

        if readingMode == .defaultViewer || readingMode == .rtl {
            sliderView.direction = .backward
        } else {
            sliderView.direction = .forward
        }

        if readingMode == .scroll && !(pageManager is ReaderScrollPageManager) {
            pageManager = ReaderScrollPageManager()
        } else if !(pageManager is ReaderPagedPageManager) {
            pageManager = ReaderPagedPageManager()
        } else {
            ignoreSet = true
            pageManager.readingMode = readingMode
        }
    }

    func activateConstraints() {
        currentPageLabel.centerXAnchor.constraint(equalTo: toolbarView.centerXAnchor).isActive = true
        currentPageLabel.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor).isActive = true

        pagesLeftLabel.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -16).isActive = true
        pagesLeftLabel.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor).isActive = true

        sliderView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        sliderView.topAnchor.constraint(equalTo: toolbarView.topAnchor, constant: 10).isActive = true
        sliderView.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 12).isActive = true
        sliderView.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -12).isActive = true

        toolbarSliderWidthConstraint?.isActive = true

        transitionView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        transitionView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

//        transitionView.isHidden = false

        toolbarSliderWidthConstraint?.constant = size.width

        pageManager.willTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
//            self.transitionView.isHidden = true
            self.updateLabels()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
}

extension ReaderViewController {

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        let page = Int(round(sender.currentValue * CGFloat(pageManager.pages.count - 1)))
        currentPageLabel.text = "\(page + 1) of \(pageManager.pages.count)"
    }

    @objc func sliderDone(_ sender: ReaderSliderView) {
        let page = Int(round(sender.currentValue * CGFloat(pageManager.pages.count - 1)))
        pageManager.move(toPage: page)
    }

    func updateLabels() {
        var currentPage = currentPageIndex + 1
        let pageCount = pageManager.pages.count
        if currentPage > pageCount {
            currentPage = pageCount
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = pageCount - currentPage
        let page = currentPage
        Task { @MainActor in
            self.currentPageLabel.text = "\(page) of \(pageCount)"
            if pagesLeft < 1 {
                self.pagesLeftLabel.text = nil
            } else {
                self.pagesLeftLabel.text = "\(pagesLeft) page\(pagesLeft == 1 ? "" : "s") left"
            }
            self.sliderView.move(toValue: CGFloat(page - 1) / max(CGFloat(pageCount - 1), 1))
        }
    }

    @MainActor
    func loadChapter() async {
        if let manga = manga {
            DataManager.shared.setRead(manga: manga)
        }
        DataManager.shared.addHistory(for: chapter)

        navigationItem.setTitle(
            upper: chapter.volumeNum != nil ? String(format: "Volume %g", chapter.volumeNum ?? 0) : nil,
            lower: String(format: "Chapter %g", chapter.chapterNum ?? 0)
        )

        if chapterList.isEmpty {
            chapterList = await DataManager.shared.getChapters(from: chapter.sourceId, for: chapter.mangaId, fromSource: true)
        }
    }

    @objc func close() {
        var index = currentPageIndex
        let pageCount = pageManager.pages.count
        if index < 0 {
            index = 0
        } else if index >= pageCount {
            index = pageCount - 1
        }
        DataManager.shared.setCurrentPage(index, for: chapter)
        self.dismiss(animated: true)
    }

    @objc func openChapterSelectionPopover(_ sender: UIBarButtonItem) {
        let vc = ChapterListPopoverContentController(chapterList: chapterList, selectedIndex: chapterList.firstIndex(of: chapter) ?? 0)
        vc.delegate = self
        vc.preferredContentSize = CGSize(width: 300, height: 250)
        vc.modalPresentationStyle = .popover
        vc.presentationController?.delegate = self
        vc.popoverPresentationController?.permittedArrowDirections = .up
        vc.popoverPresentationController?.barButtonItem = sender
        present(vc, animated: true)
    }

    @objc func openReaderSettings(_ sender: UIBarButtonItem) {
        let vc = UINavigationController(rootViewController: ReaderSettingsViewController())
        present(vc, animated: true)
    }

    @objc func toggleBarVisibility() {
        if let navigationController = navigationController {
            if navigationController.navigationBar.alpha > 0 {
                hideBars()
            } else {
                showBars()
            }
        }
    }

    func showBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = false
                self.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            } completion: { _ in
                if navigationController.toolbar.isHidden {
                    navigationController.toolbar.alpha = 0
                    navigationController.toolbar.isHidden = false
                }
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 1
                    navigationController.toolbar.alpha = 1
                    self.view.backgroundColor = .systemBackground
                }
            }
        }
    }

    func hideBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = true
                self.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            } completion: { _ in
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 0
                    navigationController.toolbar.alpha = 0
                    self.view.backgroundColor = .black
                } completion: { _ in
                    navigationController.toolbar.isHidden = true
                }
            }
        }
    }
}

// MARK: - Page Manager Delegate
extension ReaderViewController: ReaderPageManagerDelegate {

    func didMove(toPage page: Int) {
        currentPageIndex = page
        updateLabels()
        var index = page
        let pageCount = pageManager.pages.count
        if index < 0 {
            index = 0
        } else if index >= pageCount {
            index = pageCount - 1
        }
        DataManager.shared.setCurrentPage(index, for: chapter)
    }

    func pagesLoaded() {
        Task { @MainActor in
            updateLabels()
            progressView.stopAnimating()
        }
    }

    func move(toChapter chapter: Chapter) {
        self.chapter = chapter
        Task {
            await loadChapter()
        }
    }
}

// MARK: - Chapter List Delegate
extension ReaderViewController: ChapterListPopoverDelegate {
    func chapterSelected(_ chapter: Chapter) {
        self.chapter = chapter
        pageManager.setChapter(chapter: chapter, startPage: DataManager.shared.currentPage(for: chapter))
        Task {
            await loadChapter()
        }
    }
}

// MARK: - Popover Delegate
extension ReaderViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
