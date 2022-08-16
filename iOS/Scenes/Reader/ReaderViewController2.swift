//
//  ReaderViewController2.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import UIKit

class ReaderViewController2: BaseViewController {

    var chapter: Chapter

    var chapterList: [Chapter] = []
    var currentPage = 1

    weak var reader: ReaderReaderDelegate?

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private lazy var tapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
        tap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)

        return tap
    }()

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

    init(chapter: Chapter, chapterList: [Chapter] = []) {
        self.chapter = chapter
        self.chapterList = chapterList
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        // navbar buttons
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
                action: nil
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
                action: #selector(openReaderSettings)
            )
        ]
        navigationItem.rightBarButtonItems?.first?.isEnabled = false

        // fix navbar being clear
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

        // toolbar view
        toolbarView.sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        toolbarView.sliderView.addTarget(self, action: #selector(sliderStopped(_:)), for: .editingDidEnd)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        let toolbarButtonItemView = UIBarButtonItem(customView: toolbarView)
        toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -10)
        toolbarButtonItemView.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)

        toolbarItems = [toolbarButtonItemView]
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.fitContentViewToToolbar()

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // bar toggle tap gesture
        view.addGestureRecognizer(tapGesture)

        // load chapter list
        Task {
            if chapterList.isEmpty {
                await loadChapterList()
            }

            // TODO: change
            navigationItem.setTitle(
                upper: chapter.volumeNum ?? 0 != 0 ? String(format: NSLocalizedString("VOLUME_X", comment: ""), chapter.volumeNum!) : nil,
                lower: String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapter.chapterNum ?? 0)
            )

            let pageController = ReaderPagedViewController()
            pageController.delegate = self
            reader = pageController
            add(child: pageController)

            let startPage = CoreDataManager.shared.getProgress(
                sourceId: chapter.sourceId,
                mangaId: chapter.mangaId,
                chapterId: chapter.id
            )
            currentPage = startPage
            reader?.setChapter(chapter, startPage: startPage)
        }

//        activityIndicator.stopAnimating()
//        toolbarView.totalPages = 12
//        toolbarView.currentPage = 1
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Task {
            await CoreDataManager.shared.setProgress(
                currentPage,
                sourceId: chapter.sourceId,
                mangaId: chapter.mangaId,
                chapterId: chapter.id
            )
            NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
        }
    }

    func loadChapterList() async {
        chapterList = (try? await SourceManager.shared.source(for: chapter.sourceId)?
            .getChapterList(manga: Manga(sourceId: chapter.sourceId, id: chapter.mangaId))) ?? []
    }

    @objc func openReaderSettings() {
        let vc = UINavigationController(rootViewController: ReaderSettingsViewController())
        present(vc, animated: true)
    }

    @objc func close() {
        dismiss(animated: true)
    }

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        reader?.sliderMoved(value: sender.currentValue)
    }
    @objc func sliderStopped(_ sender: ReaderSliderView) {
        reader?.sliderStopped(value: sender.currentValue)
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController2: ReaderHoldingDelegate {

    func getChapter() -> Chapter {
        chapter
    }

    func getNextChapter() -> Chapter? {
        guard
            let index = chapterList.firstIndex(of: chapter),
            index + 1 < chapterList.count
        else {
            return nil
        }
        return chapterList[index + 1]
    }

    func getPreviousChapter() -> Chapter? {
        guard
            let index = chapterList.firstIndex(of: chapter),
            index - 1 >= 0
        else {
            return nil
        }
        return chapterList[index - 1]
    }

    func setChapter(_ chapter: Chapter) {
        self.chapter = chapter
    }

    func setCurrentPage(_ page: Int) {
        guard page > 0 && page <= toolbarView.totalPages ?? Int.max else { return }
        currentPage = page
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
    }

    func setTotalPages(_ pages: Int) {
        toolbarView.totalPages = pages
        activityIndicator.stopAnimating()
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }
}

// MARK: - Bar Visibility
extension ReaderViewController2 {

    @objc func toggleBarVisibility() {
        guard let navigationController = navigationController else { return }
        if navigationController.navigationBar.alpha > 0 {
            hideBars()
        } else {
            showBars()
        }
    }

    func showBars() {
        guard let navigationController = navigationController else { return }
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

    func hideBars() {
        guard let navigationController = navigationController else { return }
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
