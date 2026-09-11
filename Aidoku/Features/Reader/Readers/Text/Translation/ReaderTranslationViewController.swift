import AidokuRunner
import SwiftUI
import Translation

@available(iOS 18.0, *)
final class ReaderTranslationViewController: BaseObservingViewController, ReaderBookReader {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let model: BookTranslationModel
    var translationModel: BookTranslationModel? { model }
    var readingMode: ReadingMode = .ltr
    weak var delegate: ReaderHoldingDelegate?
    private var chapter: AidokuRunner.Chapter?
    private var loadTask: Task<Void, Never>?
    private var loadID = UUID()
    private var position: Double = 0
    private var pageCount = 2
    private let navigation = BookTranslationNavigation()

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
        self.source = source
        self.manga = manga
        model = .init(source: source, manga: manga)
        super.init()
    }

    override func configure() {
        let host = UIHostingController(rootView: BookTranslationReaderView(
            model: model, navigation: navigation,
            onProgress: { [weak self] in self?.reportProgress($0) },
            onChapterChange: { [weak self] in self?.loadAdjacent(next: $0) }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    override func observe() {
        addObserver(forName: BookTranslationSettings.changed) { [weak self] _ in self?.model.updateSettings() }
        for key in [
            "Reader.textFontFamily", "Reader.textFontSize", "Reader.textLineSpacing",
            "Reader.textHorizontalPadding", ReaderTextTheme.changeNotification
        ] {
            addObserver(forName: key) { [weak self] _ in self?.model.styleRevision += 1 }
        }
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil {
            loadTask?.cancel()
            model.cancel()
        }
    }

    func requestTranslation() { model.translate() }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        loadChapter(chapter, startPage: startPage, initialPosition: 0)
    }

    private func loadChapter(_ chapter: AidokuRunner.Chapter, startPage: Int, initialPosition: Double) {
        loadTask?.cancel()
        let id = UUID()
        loadID = id
        self.chapter = chapter
        position = initialPosition
        navigation.previousTitle = nil
        navigation.nextTitle = nil
        model.reset(chapter: chapter)
        navigation.move(to: 0)
        loadTask = Task { [weak self] in
            guard let self else { return }
            let blocks: [BookTranslationBlock]
            if let cached = model.cachedBlocks(for: chapter) {
                blocks = cached
            } else {
                let loader = ReaderTextViewModel(source: source, manga: manga)
                await loader.loadPages(chapter: chapter)
                guard !Task.isCancelled, loadID == id else { return }
                guard !loader.pages.isEmpty, loader.pages.allSatisfy(\.isTextPage) else {
                    model.loading = false
                    delegate?.setPages(loader.pages)
                    return
                }
                let texts = loader.pages.map(ReaderTextContent.load)
                guard texts.allSatisfy({ $0 != nil }) else {
                    model.loading = false
                    model.error = NSLocalizedString("TRANSLATION_EMPTY_CHAPTER")
                    return
                }
                blocks = texts.compactMap { $0 }.flatMap(BookTranslationBlock.parse)
            }
            var restored = initialPosition
            if startPage > 0 {
                let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
                restored = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.getHistory(chapterId: identifier, context: context)?.scrollPosition?.doubleValue ?? 0
                }
            }
            guard !Task.isCancelled, loadID == id else { return }
            pageCount = max(2, blocks.count)
            var marker = Page(sourceId: manga.sourceKey, chapterId: chapter.key)
            marker.text = "page"
            delegate?.setPages(Array(repeating: marker, count: pageCount))
            updateAdjacentChapters()
            model.loaded(blocks: blocks, next: delegate?.getNextChapter())
            navigation.move(to: restored)
            reportProgress(restored)
        }
    }

    func updateAdjacentChapters() {
        let previous = delegate?.getPreviousChapter()
        let next = delegate?.getNextChapter()
        navigation.previousTitle = previous.map { $0.formattedTitle() }
        navigation.nextTitle = next.map { $0.formattedTitle() }
        model.updateNextChapter(next)
    }

    private func reportProgress(_ progress: Double) {
        guard !model.loading, !model.blocks.isEmpty else { return }
        position = min(1, max(0, progress))
        let page = position >= 0.999 ? pageCount : min(pageCount - 1, Int(position * Double(pageCount - 1)) + 1)
        delegate?.setCurrentPage(page, position: position)
        delegate?.setSliderOffset(CGFloat(position))
    }

    private func loadAdjacent(next: Bool) {
        guard !model.loading, let chapter = next ? delegate?.getNextChapter() : delegate?.getPreviousChapter() else { return }
        delegate?.setChapter(chapter)
        loadChapter(chapter, startPage: 0, initialPosition: next ? 0 : 1)
    }

    func moveLeft() {
        if position <= 0 { loadAdjacent(next: false) } else { navigation.move(to: max(0, position - 1 / Double(pageCount))) }
    }

    func moveRight() {
        if position >= 0.999 { loadAdjacent(next: true) } else { navigation.move(to: min(1, position + 1 / Double(pageCount))) }
    }

    func sliderMoved(value: CGFloat) { navigation.move(to: Double(value)) }
    func sliderStopped(value: CGFloat) { navigation.move(to: Double(value)) }
}

@available(iOS 18.0, *)
@MainActor
private final class BookTranslationNavigation: ObservableObject {
    @Published var previousTitle: String?
    @Published var nextTitle: String?
    @Published var position: Double = 0
    @Published var revision = 0
    func move(to position: Double) {
        self.position = position
        revision += 1
    }
}

@available(iOS 18.0, *)
private struct BookTranslationReaderView: View {
    @ObservedObject var model: BookTranslationModel
    @ObservedObject var navigation: BookTranslationNavigation
    let onProgress: (Double) -> Void
    let onChapterChange: (Bool) -> Void

    var body: some View {
        BookTranslationPanes(
            model: model, position: navigation.position,
            positionRevision: navigation.revision, onProgress: onProgress,
            previousTitle: navigation.previousTitle, nextTitle: navigation.nextTitle,
            onChapterChange: onChapterChange
        )
        .background(Color(uiColor: ReaderTextTheme.getCurrentBackground()))
        .overlay {
            if model.loading { ProgressView() }
        }
        .overlay { BookTranslationSessionView(model: model) }
    }
}

@available(iOS 18.0, *)
struct BookTranslationTaskView: View {
    let model: BookTranslationModel
    let job: BookTranslationModel.Job

    var body: some View {
        Color.clear
            .translationTask(.init(
                source: job.settings.source.isEmpty ? nil : .init(identifier: job.settings.source),
                target: job.settings.target.isEmpty ? nil : .init(identifier: job.settings.target)
            )) { session in
                await model.run(job, session: session)
            }
    }
}
