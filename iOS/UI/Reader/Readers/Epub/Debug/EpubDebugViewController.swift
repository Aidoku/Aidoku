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

/// Renders one spine document in the locked-down web view.
private class EpubDebugRenderViewController: UIViewController {
    private let bookURL: URL
    private let spinePath: String
    private var webView: WKWebView?

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

        title = (spinePath as NSString).lastPathComponent
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Checks",
            style: .plain,
            target: self,
            action: #selector(runChecks)
        )

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

        let configuration = await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.webView = webView

        guard let url = EpubSchemeHandler.url(forResourcePath: spinePath) else {
            return show(title: "Load", message: "could not build a url for \(spinePath)")
        }
        // Loading over the custom scheme means relative subresource requests resolve against it
        // too, so they arrive back at the handler.
        webView.load(URLRequest(url: url))
    }

    /// Reports whether remote resources were blocked, which is the posture this slice exists to
    /// establish. A blocked image never decodes, so its `naturalWidth` stays at zero, and a
    /// blocked stylesheet never enters `document.styleSheets`.
    @objc private func runChecks() {
        Task {
            do {
                let report = try await evaluate(Self.checkScript)
                show(title: "Checks", message: (report as? String) ?? "unexpected result: \(String(describing: report))")
            } catch {
                show(title: "Checks", message: "\(error)")
            }
        }
    }

    /// The completion-handler form is used deliberately. On current WebKit every content-world
    /// variant of the `async` overload resolves to `()` regardless of what the script returns.
    private func evaluate(_ script: String) async throws -> Any? {
        guard let webView else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: EpubWebViewFactory.contentWorld) { result in
                switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                }
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

extension EpubDebugRenderViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Alongside the content rule list, which is what stops subresource loads: only our own
        // scheme is allowed to navigate.
        navigationAction.request.url?.scheme == EpubSchemeHandler.scheme ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        show(title: "Navigation", message: "\(error)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        show(title: "Navigation", message: "\(error)")
    }
}

#endif
