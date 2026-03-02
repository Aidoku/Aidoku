//
//  TextDoublePageViewController.swift
//  Aidoku

import UIKit

class TextDoublePageViewController: UIViewController {
    enum Direction {
        case ltr
        case rtl
    }

    let leftPage: TextPage
    let rightPage: TextPage
    let direction: Direction
    weak var parentReader: ReaderPagedTextViewController?

    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 1
        return sv
    }()

    private lazy var leftTextView: UITextView = createTextView()
    private lazy var rightTextView: UITextView = createTextView()
    private lazy var dividerView: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        return v
    }()

    init(leftPage: TextPage, rightPage: TextPage, direction: Direction, parentReader: ReaderPagedTextViewController? = nil) {
        self.leftPage = leftPage
        self.rightPage = rightPage
        self.direction = direction
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        view.addSubview(dividerView)
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if direction == .rtl {
            stackView.addArrangedSubview(rightTextView)
            stackView.addArrangedSubview(leftTextView)
            rightTextView.attributedText = rightPage.attributedContent
            leftTextView.attributedText = leftPage.attributedContent
        } else {
            stackView.addArrangedSubview(leftTextView)
            stackView.addArrangedSubview(rightTextView)
            leftTextView.attributedText = leftPage.attributedContent
            rightTextView.attributedText = rightPage.attributedContent
        }

        // Pin to view edges (not safe area) so text doesn't shift when bars hide/show.
        // The paginator already accounts for toolbar/safe-area space via its buffer.
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dividerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: 20),
            dividerView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: -20),
            dividerView.widthAnchor.constraint(equalToConstant: 1)
        ])

        updateTextInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTextInsets()
    }

    /// Position text content within the full-screen view by accounting for safe area
    /// and toolbar buffer. Keeps text stable when bars hide/show.
    private func updateTextInsets() {
        let safeArea = view.safeAreaInsets
        let toolbarBuffer: CGFloat = 100
        let verticalPadding: CGFloat = 32
        let horizontalPadding: CGFloat = 24

        let topInset = safeArea.top + toolbarBuffer / 2 + verticalPadding
        let bottomInset = safeArea.bottom + toolbarBuffer / 2 + verticalPadding
        let leftInset = safeArea.left + horizontalPadding
        let rightInset = safeArea.right + horizontalPadding

        let insets = UIEdgeInsets(
            top: topInset, left: leftInset,
            bottom: bottomInset, right: rightInset
        )
        leftTextView.textContainerInset = insets
        rightTextView.textContainerInset = insets
    }

    private func createTextView() -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .systemBackground
        return tv
    }
}
