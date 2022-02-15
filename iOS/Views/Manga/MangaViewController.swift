//
//  MangaViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/30/22.
//

import UIKit
import SafariServices
import Kingfisher

// MARK: - Manga Header View
class MangaViewHeaderView: UIView {
    
    var host: UIViewController? {
        didSet {
            descriptionLabel.host = host
        }
    }
    
    var manga: Manga? {
        didSet {
            activateConstraints()
            updateViews()
        }
    }
    
    var inLibrary: Bool {
        guard let manga = manga else { return false }
        return DataManager.shared.libraryContains(manga: manga)
    }
    
    let contentStackView = UIStackView()
    
    let titleStackView = UIStackView()
    let coverImageView = UIImageView()
    let innerTitleStackView = UIStackView()
    let titleLabel = UILabel()
    let authorLabel = UILabel()
    let labelStackView = UIStackView()
    let statusView = UIView()
    let statusLabel = UILabel()
    let nsfwView = UIView()
    let nsfwLabel = UILabel()
    let buttonStackView = UIStackView()
    let bookmarkButton = UIButton(type: .roundedRect)
    let safariButton = UIButton(type: .roundedRect)
    let descriptionLabel = ExpandableTextView()
    let tagScrollView = UIScrollView()
    let readButton = UIButton(type: .roundedRect)
    let headerView = UIView()
    let headerTitle = UILabel()
    let sortButton = UIButton(type: .roundedRect)
    
    override var intrinsicContentSize: CGSize {
        return CGSize(
            width: bounds.width,
            height: contentStackView.bounds.height + 10
        )
    }
    
    init(manga: Manga) {
        self.manga = manga
        super.init(frame: .zero)
        configureContents()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureContents()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateViews() {
        let retry = DelayRetryStrategy(maxRetryCount: 5, retryInterval: .seconds(0.1))
        coverImageView.kf.setImage(
            with: URL(string: manga?.cover ?? ""),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: [
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry),
                .cacheOriginalImage
            ]
        )
        titleLabel.text = manga?.title ?? "No Title"
        authorLabel.text = manga?.author ?? "No Author"
        statusLabel.text = manga?.status == .ongoing ? "Ongoing" : manga?.status == .cancelled ? "Cancelled" : manga?.status == .completed ? "Completed" : manga?.status == .hiatus ? "Hiatus" : "Unknown"
        self.statusView.isHidden = self.manga?.status == .unknown
        if manga?.nsfw == .safe {
            nsfwView.alpha = 0
        } else {
            if manga?.nsfw == .suggestive {
                nsfwLabel.text = "Suggestive"
                nsfwView.backgroundColor = .systemOrange.withAlphaComponent(0.3)
            } else if manga?.nsfw == .nsfw {
                nsfwLabel.text = "NSFW"
                nsfwView.backgroundColor = .systemRed.withAlphaComponent(0.3)
            }
            nsfwView.alpha = 1
        }
        if inLibrary {
            bookmarkButton.tintColor = .white
            bookmarkButton.backgroundColor = tintColor
        } else {
            bookmarkButton.tintColor = tintColor
            bookmarkButton.backgroundColor = .secondarySystemFill
        }
        
        descriptionLabel.text = manga?.description ?? "No Description"
        
        UIView.animate(withDuration: 0.3) {
            self.labelStackView.isHidden = self.manga?.status == .unknown && self.manga?.nsfw == .safe
            
            if (self.descriptionLabel.alpha == 0 || self.descriptionLabel.isHidden) && self.manga?.description != nil  {
                self.descriptionLabel.alpha = 1
                self.descriptionLabel.isHidden = false
            }
            
            let targetAlpha: CGFloat = self.manga?.url == nil ? 0 : 1
            if self.safariButton.alpha != targetAlpha {
                self.safariButton.alpha = targetAlpha
            }
        } completion: { _ in
            // Necessary because pre-iOS 15 stack view won't adjust its size automatically for some reason
            self.labelStackView.isHidden = self.manga?.status == .unknown && self.manga?.nsfw == .safe
        }
        loadTags()
        layoutIfNeeded()
    }
    
    func configureContents() {
        contentStackView.distribution = .fill
        contentStackView.axis = .vertical
        contentStackView.spacing = 14
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStackView)
        
        titleStackView.distribution = .fillProportionally
        titleStackView.axis = .horizontal
        titleStackView.spacing = 12
        titleStackView.alignment = .bottom
        titleStackView.translatesAutoresizingMaskIntoConstraints = false

        // Cover image
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 5
        coverImageView.layer.cornerCurve = .continuous
        coverImageView.layer.borderWidth = 1
        coverImageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.addArrangedSubview(coverImageView)

        innerTitleStackView.distribution = .fill
        innerTitleStackView.axis = .vertical
        innerTitleStackView.spacing = 4
        innerTitleStackView.alignment = .leading
        titleStackView.addArrangedSubview(innerTitleStackView)

        // Title
        titleLabel.numberOfLines = 3
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        innerTitleStackView.addArrangedSubview(titleLabel)

        // Author
        authorLabel.numberOfLines = 1
        authorLabel.font = .systemFont(ofSize: 16)
        authorLabel.textColor = .secondaryLabel
        innerTitleStackView.addArrangedSubview(authorLabel)
        innerTitleStackView.setCustomSpacing(7, after: authorLabel)

        // Labels
        labelStackView.distribution = .equalSpacing
        labelStackView.axis = .horizontal
        labelStackView.spacing = 6
        innerTitleStackView.addArrangedSubview(labelStackView)
        innerTitleStackView.setCustomSpacing(10, after: labelStackView)

        // Status label
        statusView.isHidden = manga?.status == .unknown
        statusView.backgroundColor = .tertiarySystemFill
        statusView.layer.cornerRadius = 6
        statusView.layer.cornerCurve = .continuous

        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(statusLabel)
        labelStackView.addArrangedSubview(statusView)

        // Content rating label
        nsfwView.layer.cornerRadius = 6
        nsfwView.layer.cornerCurve = .continuous

        nsfwLabel.textColor = .secondaryLabel
        nsfwLabel.font = .systemFont(ofSize: 10)
        nsfwLabel.textAlignment = .center
        nsfwLabel.translatesAutoresizingMaskIntoConstraints = false
        nsfwView.addSubview(nsfwLabel)
        labelStackView.addArrangedSubview(nsfwView)

        // Buttons
        buttonStackView.distribution = .equalSpacing
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 8
        innerTitleStackView.addArrangedSubview(buttonStackView)

        // Bookmark button
        bookmarkButton.addTarget(self, action: #selector(bookmarkPressed), for: .touchUpInside)
        bookmarkButton.setImage(UIImage(systemName: "bookmark.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        bookmarkButton.layer.cornerRadius = 6
        bookmarkButton.layer.cornerCurve = .continuous
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.addArrangedSubview(bookmarkButton)
        
        // Webview button
        if manga?.url == nil {
            safariButton.alpha = 0
        }
        safariButton.backgroundColor = .secondarySystemFill
        safariButton.setImage(UIImage(systemName: "safari", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        safariButton.layer.cornerRadius = 6
        safariButton.layer.cornerCurve = .continuous
        safariButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.addArrangedSubview(safariButton)

        contentStackView.addArrangedSubview(titleStackView)

        // Description
        descriptionLabel.host = host
        descriptionLabel.alpha = manga?.description == nil ? 0 : 1
        descriptionLabel.isHidden = manga?.description == nil
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(descriptionLabel)
        contentStackView.setCustomSpacing(12, after: descriptionLabel)

        tagScrollView.showsVerticalScrollIndicator = false
        tagScrollView.showsHorizontalScrollIndicator = false
        tagScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(tagScrollView)
        contentStackView.setCustomSpacing(16, after: tagScrollView)

        // Read button
        readButton.tintColor = .white
        readButton.setTitle("No chapters available", for: .normal)
        readButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        readButton.backgroundColor = tintColor
        readButton.layer.cornerRadius = 10
        readButton.layer.cornerCurve = .continuous
        readButton.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(readButton)
        contentStackView.setCustomSpacing(12, after: readButton)
        
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(headerView)
        
        // Chapter count header text
        headerTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTitle)
        
        if #available(iOS 15.0, *) {
            sortButton.setImage(UIImage(systemName: "line.3.horizontal.decrease"), for: .normal)
        } else {
            sortButton.setImage(UIImage(systemName: "line.horizontal.3.decrease"), for: .normal)
        }
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(sortButton)
        
        activateConstraints()
        updateViews()
        
        contentStackView.frame = CGRect(origin: .zero, size: contentStackView.intrinsicContentSize)
    }
    
    func activateConstraints() {
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentStackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            
            coverImageView.widthAnchor.constraint(equalToConstant: 114),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 3/2),
            
            bookmarkButton.widthAnchor.constraint(equalToConstant: 40),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 32),
            safariButton.widthAnchor.constraint(equalToConstant: 40),
            safariButton.heightAnchor.constraint(equalToConstant: 32),
            
            statusLabel.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 8),
            statusView.widthAnchor.constraint(equalTo: statusLabel.widthAnchor, constant: 16),
            statusView.heightAnchor.constraint(equalTo: statusLabel.heightAnchor, constant: 8),

            nsfwView.widthAnchor.constraint(equalTo: nsfwLabel.widthAnchor, constant: 16),
            nsfwView.heightAnchor.constraint(equalTo: nsfwLabel.heightAnchor, constant: 8),
            nsfwLabel.leadingAnchor.constraint(equalTo: nsfwView.leadingAnchor, constant: 8),
            nsfwLabel.topAnchor.constraint(equalTo: nsfwView.topAnchor, constant: 4),
            
            descriptionLabel.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),
            descriptionLabel.heightAnchor.constraint(equalTo: descriptionLabel.textLabel.heightAnchor),
            
            tagScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tagScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tagScrollView.heightAnchor.constraint(equalToConstant: 26),
            
            readButton.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            readButton.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),
            readButton.heightAnchor.constraint(equalToConstant: 38),
            
            headerView.heightAnchor.constraint(equalToConstant: 36),
            
            headerTitle.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerTitle.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            sortButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            sortButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }
    
    override func tintColorDidChange() {
        super.tintColorDidChange()
        readButton.backgroundColor = tintColor
        if inLibrary {
            bookmarkButton.backgroundColor = tintColor
        } else {
            bookmarkButton.tintColor = tintColor
        }
    }
    
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        loadTags()
    }
    
    func loadTags() {
        for view in tagScrollView.subviews {
            view.removeFromSuperview()
        }
        
        var width: CGFloat = safeAreaInsets.left + 16
        for tag in manga?.tags ?? [] {
            let tagView = UIView()
            tagView.backgroundColor = .tertiarySystemFill
            tagView.layer.cornerRadius = 13
            tagView.translatesAutoresizingMaskIntoConstraints = false
            tagScrollView.addSubview(tagView)
            
            let tagLabel = UILabel()
            tagLabel.text = tag
            tagLabel.textColor = .secondaryLabel
            tagLabel.font = .systemFont(ofSize: 14)
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            tagView.addSubview(tagLabel)
            
            tagView.leadingAnchor.constraint(equalTo: tagScrollView.leadingAnchor, constant: width).isActive = true
            tagLabel.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: 12).isActive = true
            tagLabel.topAnchor.constraint(equalTo: tagView.topAnchor, constant: 4).isActive = true
            tagView.widthAnchor.constraint(equalTo: tagLabel.widthAnchor, constant: 24).isActive = true
            tagView.heightAnchor.constraint(equalTo: tagLabel.heightAnchor, constant: 8).isActive = true
            
            width += tagLabel.intrinsicContentSize.width + 24 + 10
        }
        tagScrollView.contentSize = CGSize(width: width + 16, height: 26)
        
        UIView.animate(withDuration: 0.3) {
            self.tagScrollView.isHidden = (self.manga?.tags ?? []).isEmpty
        } completion: { _ in
            self.tagScrollView.isHidden = (self.manga?.tags ?? []).isEmpty
        }
    }
    
    @objc func bookmarkPressed() {
        if let manga = manga {
            if inLibrary {
                DataManager.shared.delete(manga: manga)
            } else {
                _ = DataManager.shared.addToLibrary(manga: manga)
            }
            if inLibrary {
                bookmarkButton.tintColor = .white
                bookmarkButton.backgroundColor = tintColor
            } else {
                bookmarkButton.tintColor = tintColor
                bookmarkButton.backgroundColor = .secondarySystemFill
            }
        }
    }
}

// MARK: - Manga View Controller
class MangaViewController: UIViewController {
    
    var manga: Manga {
        didSet {
            (tableView.tableHeaderView as? MangaViewHeaderView)?.manga = manga
            view.setNeedsLayout()
        }
    }
    
    var chapters: [Chapter] {
        didSet {
            if chapters.count > 0 {
                (tableView.tableHeaderView as? MangaViewHeaderView)?.headerTitle.text = "\(chapters.count) chapters"
            } else {
                (tableView.tableHeaderView as? MangaViewHeaderView)?.headerTitle.text = "No chapters"
            }
            updateReadButton()
        }
    }
    var sortedChapters: [Chapter] {
        if sortOption == 0 {
            return sortAscending ? chapters.reversed() : chapters
        } else if sortOption == 1 {
            return sortAscending ? orderedChapters.reversed() : orderedChapters
        } else {
            return chapters
        }
    }
    var orderedChapters: [Chapter] {
        chapters.sorted { a, b in
            a.chapterNum ?? -1 < b.chapterNum ?? -1
        }
    }
    var readHistory: [String: Int] = [:]
    
    var tintColor: UIColor? {
        didSet {
            setTintColor(tintColor)
        }
    }
    
    var sortOption: Int = 0 {
        didSet {
            tableView.reloadData()
        }
    }
    var sortAscending: Bool = false {
        didSet {
            tableView.reloadData()
        }
    }
    
    let tableView = UITableView(frame: .zero, style: .grouped)
    
    init(manga: Manga, chapters: [Chapter] = []) {
        self.manga = manga
        self.chapters = chapters
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = nil
        
        navigationItem.largeTitleDisplayMode = .never
        
        // TODO: only show relevant actions
        let mangaOptions: [UIAction] = [
            UIAction(title: "Read", image: nil) { _ in
                    DataManager.shared.setCompleted(chapters: self.chapters, date: Date().addingTimeInterval(-5))
                // Make most recent chapter appear as the most recently read
                if let firstChapter = self.chapters.first {
                    DataManager.shared.setCompleted(chapter: firstChapter)
                }
                self.updateReadHistory()
                self.tableView.reloadData()
            },
            UIAction(title: "Unread", image: nil) { _ in
                for chapter in self.chapters {
                    DataManager.shared.removeHistory(for: chapter)
                }
                self.updateReadHistory()
                self.tableView.reloadData()
            }
        ]
        let markSubmenu = UIMenu(title: "Mark All", children: mangaOptions)
        
        let menu = UIMenu(title: "", children: [markSubmenu])
        
        let ellipsisButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: nil)
        ellipsisButton.menu = menu
        navigationItem.rightBarButtonItem = ellipsisButton
        
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0.0
        }
        tableView.delaysContentTouches = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        let headerView = MangaViewHeaderView(manga: manga)
        headerView.host = self
        if chapters.count > 0 {
            headerView.headerTitle.text = "\(chapters.count) chapters"
        } else {
            headerView.headerTitle.text = "No chapters"
        }
        headerView.safariButton.addTarget(self, action: #selector(openWebView), for: .touchUpInside)
        headerView.readButton.addTarget(self, action: #selector(readButtonPressed), for: .touchUpInside)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableHeaderView = headerView
        
        updateSortMenu()
        updateReadHistory()
        activateConstraints()
        
        getTintColor()
        
        guard let source = SourceManager.shared.source(for: manga.sourceId) else {
            showMissingSourceWarning()
            return
        }
        Task {
            if let newManga = try? await source.getMangaDetails(manga: manga) {
                manga = manga.copy(from: newManga)
                if chapters.isEmpty {
                    chapters = await DataManager.shared.getChapters(for: manga, fromSource: !DataManager.shared.libraryContains(manga: manga))
                    DispatchQueue.main.async {
                        self.tableView.reloadSections(IndexSet(integer: 0), with: .fade)
                    }
                }
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateReadHistory()
        tableView.reloadData()
        (tableView.tableHeaderView as? MangaViewHeaderView)?.updateViews()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setTintColor(tintColor)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTintColor(nil)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let header = tableView.tableHeaderView as? MangaViewHeaderView {
            header.contentStackView.layoutIfNeeded()
            header.frame.size.height = header.intrinsicContentSize.height
            tableView.tableHeaderView = header
        }
    }
    
    func activateConstraints() {
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        tableView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
        
        if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            headerView.topAnchor.constraint(equalTo: tableView.topAnchor).isActive = true
            headerView.widthAnchor.constraint(equalTo: tableView.widthAnchor).isActive = true
            headerView.heightAnchor.constraint(equalTo: headerView.contentStackView.heightAnchor, constant: 10).isActive = true
        }
    }
    
    func setTintColor(_ color: UIColor?) {
        if let color = color {
            navigationController?.navigationBar.tintColor = color
            navigationController?.tabBarController?.tabBar.tintColor = color
            view.tintColor = color
        } else {
            navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
            navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
//            view.tintColor = UIView().tintColor
        }
    }
    
    func getTintColor() {
        if let tintColor = manga.tintColor {
            // Adjust tint color for readability
            let luma = tintColor.luminance
            if luma >= 0.6 {
                self.tintColor = tintColor.darker(by: luma >= 0.9 ? 40 : 30)
            } else if luma <= 0.3 {
                self.tintColor = tintColor.lighter(by: luma <= 0.1 ? 30 : 20)
            } else {
                self.tintColor = tintColor
            }
        } else if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            headerView.coverImageView.image?.getColors(quality: .low) { colors in
                let luma = colors?.background.luminance ?? 0
                self.manga.tintColor = luma >= 0.9 || luma <= 0.1 ? colors?.secondary : colors?.background
                self.getTintColor()
            }
        }
    }
    
    func getNextChapter() -> Chapter? {
        let id = readHistory.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters.first { $0.id == id }
        }
        return chapters.last
    }
    
    func updateSortMenu() {
        if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            let sortOptions: [UIAction] = [
                UIAction(title: "Source Order", image: sortOption == 0 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil) { _ in
                    if self.sortOption == 0 {
                        self.sortAscending.toggle()
                    } else {
                        self.sortAscending = false
                        self.sortOption = 0
                    }
                    self.updateSortMenu()
                },
                UIAction(title: "Chapter", image: sortOption == 1 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil) { _ in
                    if self.sortOption == 1 {
                        self.sortAscending.toggle()
                    } else {
                        self.sortAscending = false
                        self.sortOption = 1
                    }
                    self.updateSortMenu()
                }
            ]
            let menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: sortOptions)
            headerView.sortButton.showsMenuAsPrimaryAction = true
            headerView.sortButton.menu = menu
        }
    }
    
    func updateReadButton(_ headerView: MangaViewHeaderView? = nil) {
        var titleString = ""
        if SourceManager.shared.source(for: manga.sourceId) == nil {
            titleString = "Unavailable"
        } else if let chapter = getNextChapter() {
            if readHistory[chapter.id] ?? 0 == 0 {
                titleString.append("Start Reading")
            } else {
                titleString.append("Continue Reading")
            }
            if let volumeNum = chapter.volumeNum {
                titleString.append(String(format: " Vol.%g", volumeNum))
            }
            if let chapterNum = chapter.chapterNum {
                titleString.append(String(format: " Ch.%g", chapterNum))
            }
        } else {
            titleString = "No chapters available"
        }
        if let headerView = headerView {
            headerView.readButton.setTitle(titleString, for: .normal)
        } else {
            (tableView.tableHeaderView as? MangaViewHeaderView)?.readButton.setTitle(titleString, for: .normal)
        }
    }
    
    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(manga: manga)
        updateReadButton()
    }
    
    func openReaderView(for chapter: Chapter) {
        let readerController = ReaderNavigationController(rootViewController: ReaderViewController(manga: manga, chapter: chapter, chapterList: chapters))
        readerController.modalPresentationStyle = .fullScreen
        present(readerController, animated: true)
    }
    
    func showMissingSourceWarning() {
        let alert = UIAlertController(title: "Missing Source", message: "The original source seems to be missing for this Manga. Please redownload it or remove this title from your library", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func readButtonPressed() {
        if let chapter = getNextChapter(), let _ = SourceManager.shared.source(for: manga.sourceId) {
            openReaderView(for: chapter)
        }
    }
    
    @objc func openWebView() {
        if let url = URL(string: manga.url ?? "") {
            let config = SFSafariViewController.Configuration()
            config.entersReaderIfAvailable = true

            let vc = SFSafariViewController(url: url, configuration: config)
            present(vc, animated: true)
        }
    }
}

// MARK: - Table View Data Source
extension MangaViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapters.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "ChapterTableViewCell")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "ChapterTableViewCell")
        }
        
        let chapter = sortedChapters[indexPath.row]
        var titleString = ""
        if let volumeNum = chapter.volumeNum {
            titleString.append(String(format: "Vol.%g ", volumeNum))
        }
        if let chapterNum = chapter.chapterNum {
            titleString.append(String(format: "Ch.%g ", chapterNum))
        }
        if (chapter.volumeNum != nil || chapter.chapterNum != nil) && chapter.title != nil {
            titleString.append("- ")
        }
        if let title = chapter.title {
            titleString.append(title)
        } else if chapter.chapterNum == nil {
            titleString = "Untitled"
        }
        cell?.textLabel?.text = titleString
        
        var subtitleString = ""
        if let dateUploaded = chapter.dateUploaded {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            subtitleString.append(formatter.string(from: dateUploaded))
        }
        if chapter.dateUploaded != nil && chapter.scanlator != nil {
            subtitleString.append(" • ")
        }
        if let scanlator = chapter.scanlator {
            subtitleString.append(scanlator)
        }
        cell?.detailTextLabel?.text = subtitleString
        
        if readHistory[chapter.id] ?? 0 > 0 {
            cell?.textLabel?.textColor = .secondaryLabel
        } else {
            cell?.textLabel?.textColor = .label
        }
        
        cell?.textLabel?.font = .systemFont(ofSize: 15)
        cell?.detailTextLabel?.font = .systemFont(ofSize: 14)
        cell?.detailTextLabel?.textColor = .secondaryLabel
        cell?.backgroundColor = .clear
        
        return cell ?? UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            let action: UIAction
            if self.readHistory[self.sortedChapters[indexPath.row].id] ?? 0 > 0 {
                action = UIAction(title: "Mark as unread", image: nil) { action in
                    DataManager.shared.removeHistory(for: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                }
            } else {
                action = UIAction(title: "Mark as read", image: nil) { action in
                    DataManager.shared.addHistory(for: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                }
            }
            let previousSubmenu = UIMenu(title: "Mark Previous", children: [
                UIAction(title: "Read", image: nil) { action in
                    DataManager.shared.addHistory(for: [Chapter](self.sortedChapters[indexPath.row ..< self.sortedChapters.count]))
                    self.updateReadHistory()
                    tableView.reloadData()
                },
                UIAction(title: "Unread", image: nil) { action in
                    DataManager.shared.removeHistory(for: [Chapter](self.sortedChapters[indexPath.row ..< self.sortedChapters.count]))
                    self.updateReadHistory()
                    tableView.reloadData()
                }
            ])
            return UIMenu(title: "", children: [action, previousSubmenu])
        }
    }
}

// MARK: - Table View Delegate
extension MangaViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if SourceManager.shared.source(for: manga.sourceId) != nil {
            openReaderView(for: sortedChapters[indexPath.row])
        }
    }
}
