import SwiftUI

@available(iOS 18.0, *)
struct BookTranslationPanes: UIViewControllerRepresentable {
    @ObservedObject var model: BookTranslationModel
    let position: Double
    let positionRevision: Int
    let onProgress: (Double) -> Void
    var previousTitle: String?
    var nextTitle: String?
    var onChapterChange: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> BookTranslationPanesController {
        BookTranslationPanesController()
    }

    func updateUIViewController(_ controller: BookTranslationPanesController, context: Context) {
        controller.onProgress = onProgress
        controller.onChapterChange = onChapterChange
        controller.setChapterLinks(previous: previousTitle, next: nextTitle)
        controller.update(
            blocks: model.blocks, translations: model.translations,
            appearance: .init(split: model.settings.split, revision: model.styleRevision),
            position: position, positionRevision: positionRevision
        )
    }
}

/// Both scroll views use matching paragraph indexes. A recursion guard prevents
/// programmatic scrolling in one pane from feeding back into the other pane.
@available(iOS 18.0, *)
final class BookTranslationPanesController: UIViewController, UIScrollViewDelegate {
    struct Appearance {
        let split: Bool
        let revision: Int
    }

    private final class Pane {
        let container = UIStackView()
        let scroll = UIScrollView()
        let stack = UIStackView()
        let previousButton = UIButton(type: .system)
        let nextButton = UIButton(type: .system)
        var hosts: [UIHostingController<AnyView>] = []

        var starts: [CGFloat] { stack.arrangedSubviews.map(\.frame.minY) }
        var heights: [CGFloat] { stack.arrangedSubviews.map(\.frame.height) }
    }

    private let original = Pane()
    private let translated = Pane()
    private let layout = UIStackView()
    private var blocks: [BookTranslationBlock] = []
    private var translations: [String?]?
    private var split = false
    private var styleRevision = -1
    private var positionRevision = -1
    private var syncing = false
    private var anchor: Double = 0
    private var lastSize = CGSize.zero
    var onProgress: ((Double) -> Void)?
    var onChapterChange: ((Bool) -> Void)?
    private var previousTitle: String?
    private var nextTitle: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        layout.axis = .vertical
        layout.distribution = .fillEqually
        layout.spacing = 0
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layout.topAnchor.constraint(equalTo: view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        for pane in [original, translated] {
            pane.container.axis = .vertical
            pane.scroll.delegate = self
            pane.scroll.alwaysBounceVertical = true
            pane.scroll.contentInsetAdjustmentBehavior = .never
            pane.stack.axis = .vertical
            pane.stack.translatesAutoresizingMaskIntoConstraints = false
            pane.scroll.addSubview(pane.stack)
            for (button, next) in [(pane.previousButton, false), (pane.nextButton, true)] {
                button.translatesAutoresizingMaskIntoConstraints = false
                button.titleLabel?.lineBreakMode = .byTruncatingTail
                button.addAction(UIAction { [weak self] _ in self?.onChapterChange?(next) }, for: .touchUpInside)
                pane.scroll.addSubview(button)
                NSLayoutConstraint.activate([
                    button.centerXAnchor.constraint(equalTo: pane.stack.centerXAnchor),
                    button.widthAnchor.constraint(equalTo: pane.stack.widthAnchor, constant: -48),
                    button.heightAnchor.constraint(equalToConstant: 60)
                ])
            }
            pane.previousButton.bottomAnchor.constraint(equalTo: pane.stack.topAnchor).isActive = true
            pane.nextButton.topAnchor.constraint(equalTo: pane.stack.bottomAnchor).isActive = true
            pane.container.addArrangedSubview(pane.scroll)
            layout.addArrangedSubview(pane.container)
            NSLayoutConstraint.activate([
                pane.stack.topAnchor.constraint(equalTo: pane.scroll.contentLayoutGuide.topAnchor),
                pane.stack.bottomAnchor.constraint(equalTo: pane.scroll.contentLayoutGuide.bottomAnchor),
                pane.stack.leadingAnchor.constraint(equalTo: pane.scroll.contentLayoutGuide.leadingAnchor),
                pane.stack.trailingAnchor.constraint(equalTo: pane.scroll.contentLayoutGuide.trailingAnchor),
                pane.stack.widthAnchor.constraint(equalTo: pane.scroll.frameLayoutGuide.widthAnchor)
            ])
        }
    }

    func setChapterLinks(previous: String?, next: String?) {
        loadViewIfNeeded()
        previousTitle = previous
        nextTitle = next
        for pane in [original, translated] {
            pane.previousButton.setTitle(previous.map { "↑ " + $0 }, for: .normal)
            pane.nextButton.setTitle(next.map { $0 + " ↓" }, for: .normal)
            pane.previousButton.isHidden = previous == nil
            pane.nextButton.isHidden = next == nil
        }
    }

    func update(
        blocks: [BookTranslationBlock], translations: [String?]?, appearance: Appearance,
        position: Double, positionRevision: Int
    ) {
        loadViewIfNeeded()
        let split = appearance.split
        let styleRevision = appearance.revision
        let contentChanged = self.blocks != blocks || self.translations != translations || self.styleRevision != styleRevision
        let layoutChanged = self.split != split
        self.blocks = blocks
        self.translations = translations
        self.split = split
        self.styleRevision = styleRevision
        syncing = true
        if contentChanged {
            populate(original, isTranslation: false)
            populate(translated, isTranslation: true)
        }
        original.container.isHidden = translations != nil && !split
        translated.container.isHidden = translations == nil
        view.backgroundColor = ReaderTextTheme.getCurrentBackground()
        let positionChanged = self.positionRevision != positionRevision
        if positionChanged {
            self.positionRevision = positionRevision
            anchor = min(1, max(0, position)) * Double(blocks.count)
        }
        if contentChanged || layoutChanged { view.setNeedsLayout() }
        view.layoutIfNeeded()
        if positionChanged, position >= 1 {
            // Returning to a chapter should show its final text, not the empty
            // alignment inset below it. Use the visible pane to find that anchor.
            let pane = original.container.isHidden ? translated : original
            anchor = BookTranslationScrollPosition.anchor(
                offset: max(0, pane.stack.bounds.height - pane.scroll.bounds.height),
                starts: pane.starts, heights: pane.heights
            )
        }
        restoreAnchor()
        syncing = false
    }

    private func populate(_ pane: Pane, isTranslation: Bool) {
        for host in pane.hosts {
            host.willMove(toParent: nil)
            pane.stack.removeArrangedSubview(host.view)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        pane.hosts = []
        let defaults = UserDefaults.standard
        let fontFamily = defaults.string(forKey: "Reader.textFontFamily") ?? "System"
        let size = defaults.object(forKey: "Reader.textFontSize") as? Double ?? 18
        let spacing = defaults.object(forKey: "Reader.textLineSpacing") as? Double ?? 8
        let padding = defaults.object(forKey: "Reader.textHorizontalPadding") as? Double ?? 24
        let color = Color(uiColor: ReaderTextTheme.getCurrentText())
        pane.container.backgroundColor = ReaderTextTheme.getCurrentBackground()
        for (index, block) in blocks.enumerated() {
            let content: AnyView
            if isTranslation, let text = translations?[index] {
                content = AnyView(
                    Text(text)
                        .font(fontFamily == "System" ? .system(size: size) : .custom(fontFamily, size: size))
                        .foregroundStyle(color)
                        .lineSpacing(spacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, padding)
                        .padding(.vertical)
                )
            } else {
                content = AnyView(MarkdownView(
                    block.markdown, fontFamily: fontFamily, fontSize: size,
                    lineSpacing: spacing, horizontalPadding: padding, textColor: color
                ))
            }
            let host = UIHostingController(rootView: content)
            host.sizingOptions = .intrinsicContentSize
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            addChild(host)
            pane.stack.addArrangedSubview(host.view)
            host.didMove(toParent: self)
            pane.hosts.append(host)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size {
            lastSize = view.bounds.size
            syncing = true
            view.layoutIfNeeded()
            restoreAnchor()
            syncing = false
        }
    }

    private func restoreAnchor() {
        for pane in [original, translated] where !pane.container.isHidden {
            // Allows even the final paragraph to align at the top in either pane.
            pane.scroll.contentInset.top = previousTitle == nil ? 0 : 60
            pane.scroll.contentInset.bottom = max(nextTitle == nil ? 0 : 60, pane.scroll.bounds.height - 1)
            let offset = BookTranslationScrollPosition.offset(anchor: anchor, starts: pane.starts, heights: pane.heights)
            pane.scroll.setContentOffset(.init(x: 0, y: offset), animated: false)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !syncing, !blocks.isEmpty else { return }
        // Only a deliberate pull past the boundary changes chapters. Layout updates
        // and synchronized scrolling in the other pane must never trigger navigation.
        let top = -scrollView.adjustedContentInset.top
        let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        if previousTitle != nil, scrollView.contentOffset.y < top - 60 {
            onChapterChange?(false)
        } else if nextTitle != nil, scrollView.contentOffset.y > bottom + 60 {
            onChapterChange?(true)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !syncing, !blocks.isEmpty else { return }
        let pane = scrollView === original.scroll ? original : translated
        anchor = BookTranslationScrollPosition.anchor(offset: scrollView.contentOffset.y, starts: pane.starts, heights: pane.heights)
        syncing = true
        let other = scrollView === original.scroll ? translated : original
        if !other.container.isHidden {
            let offset = BookTranslationScrollPosition.offset(anchor: anchor, starts: other.starts, heights: other.heights)
            other.scroll.setContentOffset(.init(x: 0, y: offset), animated: false)
        }
        syncing = false
        onProgress?(min(1, max(0, anchor / Double(blocks.count))))
    }
}
