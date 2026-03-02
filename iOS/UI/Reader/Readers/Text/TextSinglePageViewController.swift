//
//  TextSinglePageViewController.swift
//  Aidoku

import UIKit

class TextSinglePageViewController: UIViewController {
    let page: TextPage
    weak var parentReader: ReaderPagedTextViewController?

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .systemBackground
        tv.font = .systemFont(ofSize: 18)
        return tv
    }()

    init(page: TextPage, parentReader: ReaderPagedTextViewController? = nil) {
        self.page = page
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.addSubview(textView)

        textView.translatesAutoresizingMaskIntoConstraints = false

        // Pin to view edges (not safe area) so text doesn't shift when bars hide/show.
        // The paginator already accounts for toolbar/safe-area space via its buffer.
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Set the text content
        if page.attributedContent.length > 0 {
            textView.attributedText = page.attributedContent
        } else {
            textView.text = page.markdownContent
        }

        updateTextInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTextInsets()
    }

    /// Position the text content within the full-screen view by accounting
    /// for safe area insets and a toolbar buffer in the text container inset.
    /// This keeps text stable when bars hide/show (safe area changes).
    private func updateTextInsets() {
        let safeArea = view.safeAreaInsets
        let toolbarBuffer: CGFloat = 100
        let verticalPadding: CGFloat = 32
        let horizontalPadding: CGFloat = 24

        // Distribute toolbar buffer evenly between top and bottom
        let topInset = safeArea.top + toolbarBuffer / 2 + verticalPadding
        let bottomInset = safeArea.bottom + toolbarBuffer / 2 + verticalPadding
        let leftInset = safeArea.left + horizontalPadding
        let rightInset = safeArea.right + horizontalPadding

        textView.textContainerInset = UIEdgeInsets(
            top: topInset, left: leftInset,
            bottom: bottomInset, right: rightInset
        )
    }
}
