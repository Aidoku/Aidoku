//
//  EpubDebugViewController.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/10/26.
//

#if DEBUG

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
