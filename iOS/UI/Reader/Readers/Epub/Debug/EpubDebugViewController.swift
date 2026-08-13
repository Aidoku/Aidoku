//
//  EpubDebugViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/10/26.
//

#if DEBUG

import AidokuRunner
import UIKit
import WebKit

/// Debug-only entry point for the ePub resource layer.
///
/// Lists the ePubs stored in the documents directory, then the spine of a chosen book, and
/// renders a selected spine document through `EpubZipResourceProvider`. It exists to exercise the
/// resource layer before there is a reader to host it, and is expected to be deleted once the
/// reader itself lands.
class EpubDebugViewController: UITableViewController {
    private var books: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "ePub Debug"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        books = Self.findBooks()
    }

    /// Every ePub under the documents directory, which covers both the local source's `Local`
    /// folder and files staged directly into the container.
    private static func findBooks() -> [URL] {
        let root = FileManager.default.documentDirectory
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "epub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        books.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = books[indexPath.row].lastPathComponent
        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            EpubDebugSpineViewController(bookURL: books[indexPath.row]),
            animated: true
        )
    }
}

/// The spine of one book, in reading order.
private class EpubDebugSpineViewController: UITableViewController {
    private let bookURL: URL
    private var spinePaths: [String] = []

    init(bookURL: URL) {
        self.bookURL = bookURL
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = bookURL.deletingPathExtension().lastPathComponent
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        let url = bookURL
        Task {
            // Chapter grouping is not used here; flattening the chapters gives the spine in
            // reading order, which is what the resource layer is addressed by.
            let paths = await Task.detached {
                EpubParser.parse(url: url)?.chapters.flatMap(\.hrefs) ?? []
            }.value
            spinePaths = paths
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        spinePaths.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "\(indexPath.row + 1). \(spinePaths[indexPath.row])"
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            EpubDebugRenderViewController(bookURL: bookURL, spinePath: spinePaths[indexPath.row]),
            animated: true
        )
    }

    /// Opens the whole book in the real reader rather than one document in the renderer.
    ///
    /// Until slice 4 makes local ePubs produce ePub pages, nothing routes a chapter to
    /// `ReaderEpubViewController`, so this is the only way to exercise it by hand.
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let button = UIButton(type: .system)
        button.setTitle("Read the whole book", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            navigationController?.pushViewController(
                EpubDebugReaderHostViewController(bookURL: bookURL),
                animated: true
            )
        }, for: .touchUpInside)
        button.backgroundColor = .secondarySystemBackground
        return button
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        44
    }
}

/// Stands in for `ReaderViewController` so the ePub reader can be driven by hand before slice 4
/// makes it reachable.
///
/// It implements only the parts of `ReaderHoldingDelegate` the ePub reader uses, and shows what it
/// reports: the page and total in the title, and the slider position. Everything else is a stub.
/// Deleted with the rest of the debug entry point.
private class EpubDebugReaderHostViewController: UIViewController {
    private let bookURL: URL
    private let reader: ReaderEpubViewController
    private let slider = UISlider()

    private var totalPages = 0
    private var currentPage = 0

    init(bookURL: URL) {
        self.bookURL = bookURL
        let manga = AidokuRunner.Manga(sourceKey: "local", key: bookURL.lastPathComponent, title: "")
        self.reader = ReaderEpubViewController(source: nil, manga: manga, bookURL: bookURL)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // A collapsing large title changes the reader's height mid-scroll, which re-fragments the
        // document and moves every page boundary. See the viewport stability trap in slice 2.
        navigationItem.largeTitleDisplayMode = .never

        reader.delegate = self
        addChild(reader)
        reader.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reader.view)
        reader.didMove(toParent: self)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderStopped), for: [.touchUpInside, .touchUpOutside])
        view.addSubview(slider)

        NSLayoutConstraint.activate([
            reader.view.topAnchor.constraint(equalTo: view.topAnchor),
            reader.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            reader.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reader.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            slider.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])

        let left = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        view.addGestureRecognizer(left)

        // The chapter's identity is all the reader takes from it; the book comes from the URL.
        reader.setChapter(AidokuRunner.Chapter(key: bookURL.lastPathComponent), startPage: 1)
        updateTitle()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: view).x
        if x < view.bounds.width / 3 {
            reader.moveLeft()
        } else if x > view.bounds.width * 2 / 3 {
            reader.moveRight()
        } else {
            navigationController?.setNavigationBarHidden(
                !(navigationController?.isNavigationBarHidden ?? false),
                animated: true
            )
        }
    }

    @objc private func sliderMoved() {
        reader.sliderMoved(value: CGFloat(slider.value))
    }

    @objc private func sliderStopped() {
        reader.sliderStopped(value: CGFloat(slider.value))
    }

    private func updateTitle() {
        title = totalPages > 0 ? "\(currentPage) / \(totalPages)" : "measuring…"
    }
}

extension EpubDebugReaderHostViewController: ReaderHoldingDelegate {
    var barsHidden: Bool { navigationController?.isNavigationBarHidden ?? false }

    func hideBars() {
        navigationController?.setNavigationBarHidden(true, animated: true)
    }

    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}

    func setCurrentPage(_ page: Int, position: Double?) {
        currentPage = page
        updateTitle()
        guard totalPages > 1 else { return }
        slider.value = Float(page - 1) / Float(totalPages - 1)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        setCurrentPage(pages.lowerBound, position: nil)
    }

    func setPages(_ pages: [Page]) {
        totalPages = pages.count
        updateTitle()
    }

    func displayPage(_ page: Int) {
        title = totalPages > 0 ? "→ \(page) / \(totalPages)" : "measuring…"
    }

    func setSliderOffset(_ offset: CGFloat) {}

    func setCompleted() {
        title = "\(currentPage) / \(totalPages) ✓"
    }
}

/// Renders one spine document, paginated, with controls for walking its pages.
private class EpubDebugRenderViewController: UIViewController {
    private let bookURL: URL
    private let spinePath: String
    private var renderer: EpubSpineRenderer?

    private lazy var previousItem = UIBarButtonItem(
        image: UIImage(systemName: "chevron.left"),
        style: .plain,
        target: self,
        action: #selector(showPreviousPage)
    )
    private lazy var nextItem = UIBarButtonItem(
        image: UIImage(systemName: "chevron.right"),
        style: .plain,
        target: self,
        action: #selector(showNextPage)
    )

    init(bookURL: URL, spinePath: String) {
        self.bookURL = bookURL
        self.spinePath = spinePath
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateTitle()
        // A large title changes height as it collapses, and the web view is sized against what
        // the bar leaves behind. A column is `100vh` tall, so the document would re-lay out
        // mid-scroll and the text on a page would depend on how far the title had collapsed.
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground

        let checksItem = UIBarButtonItem(
            title: "Checks",
            style: .plain,
            target: self,
            action: #selector(runChecks)
        )
        navigationItem.rightBarButtonItems = [nextItem, previousItem, checksItem]
        updateControls()

        Task {
            await loadSpineDocument()
        }
    }

    private func loadSpineDocument() async {
        let provider: EpubZipResourceProvider
        do {
            provider = try EpubZipResourceProvider(url: bookURL)
        } catch {
            return show(title: "Provider", message: "\(error)")
        }

        let renderer: EpubSpineRenderer
        do {
            renderer = try await EpubSpineRenderer(provider: provider)
        } catch {
            return show(title: "Renderer", message: "\(error)")
        }

        // A late image or a change to the size of the web view moves every page boundary, so the
        // count displayed here is whatever the last measurement produced.
        renderer.onRepaginate = { [weak self] _ in
            self?.updateTitle()
            self?.updateControls()
        }
        self.renderer = renderer

        let webView = renderer.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        do {
            try await renderer.load(spinePath: spinePath)
        } catch {
            return show(title: "Load", message: "\(error)")
        }

        updateTitle()
        updateControls()
    }

    // MARK: - Pages

    @objc private func showPreviousPage() {
        showPage(offsetBy: -1)
    }

    @objc private func showNextPage() {
        showPage(offsetBy: 1)
    }

    private func showPage(offsetBy offset: Int) {
        guard let renderer else { return }
        Task {
            await renderer.showPage(renderer.currentPage + offset)
            updateTitle()
            updateControls()
        }
    }

    /// The page comes first because the bar truncates the tail of a title to fit its buttons, and
    /// the page is the number being read off this screen.
    private func updateTitle() {
        let name = (spinePath as NSString).lastPathComponent
        guard let renderer, renderer.pageCount > 0 else {
            title = name
            return
        }
        title = "\(renderer.currentPage + 1)/\(renderer.pageCount) \(name)"
    }

    private func updateControls() {
        previousItem.isEnabled = (renderer?.currentPage ?? 0) > 0
        nextItem.isEnabled = renderer.map { $0.currentPage < $0.pageCount - 1 } ?? false
    }

    /// Reports whether remote resources were blocked, which is the posture slice 1 established. A
    /// blocked image never decodes, so its `naturalWidth` stays at zero, and a blocked stylesheet
    /// never enters `document.styleSheets`.
    @objc private func runChecks() {
        guard let renderer else { return }
        Task {
            do {
                let report = try await renderer.webView.evaluateJavaScript(
                    Self.checkScript,
                    contentWorld: EpubWebViewFactory.contentWorld
                )
                // Repeated here as well as in the title, since the title is what the bar truncates.
                let position = """
                \(spinePath)
                page=\(renderer.currentPage + 1)/\(renderer.pageCount) \
                progression=\(String(format: "%.3f", renderer.progression))
                """
                let details = (report as? String) ?? "unexpected result: \(String(describing: report))"
                show(title: "Checks", message: position + "\n" + details)
            } catch {
                show(title: "Checks", message: "\(error)")
            }
        }
    }

    private func show(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .default))
        present(alert, animated: true)
    }

    private static let checkScript = """
    (function() {
        var out = [];
        out.push('innerWidth=' + window.innerWidth);
        out.push('scrollWidth=' + document.documentElement.scrollWidth);
        // A page begins at exactly index * innerWidth, so an offset that is not a whole multiple
        // of the viewport means the reader is looking at two half pages.
        out.push('pageXOffset=' + window.pageXOffset);
        var images = document.images;
        for (var i = 0; i < images.length; i++) {
            out.push(
                'img ' + images[i].getAttribute('src')
                + ' naturalWidth=' + images[i].naturalWidth
                + ' complete=' + images[i].complete
            );
        }
        var sheets = document.styleSheets;
        for (var j = 0; j < sheets.length; j++) {
            var rules;
            try {
                rules = sheets[j].cssRules ? sheets[j].cssRules.length : 'null';
            } catch (e) {
                rules = 'unreadable';
            }
            out.push('sheet ' + (sheets[j].href || '(inline)') + ' rules=' + rules);
        }
        return out.join('\\n');
    })();
    """
}

#endif
