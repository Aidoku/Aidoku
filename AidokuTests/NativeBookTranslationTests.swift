import AidokuRunner
import SwiftUI
import Testing
@testable import Aidoku

@Suite(.serialized) @MainActor
struct NativeBookTranslationTests {
    private func preferences() -> () -> Void {
        let keys = [BookTranslationSettings.enabledKey, BookTranslationSettings.automaticKey, BookTranslationSettings.aheadKey,
                    BookTranslationSettings.sourceKey, BookTranslationSettings.targetKey, BookTranslationSettings.splitKey]
        let defaults = UserDefaults.standard
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(true, forKey: BookTranslationSettings.enabledKey)
        defaults.set(false, forKey: BookTranslationSettings.automaticKey)
        defaults.set(false, forKey: BookTranslationSettings.aheadKey)
        defaults.set(false, forKey: BookTranslationSettings.splitKey)
        defaults.set("", forKey: BookTranslationSettings.sourceKey)
        defaults.set("", forKey: BookTranslationSettings.targetKey)
        return { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
    }

    private func book() -> AidokuRunner.Manga {
        .init(sourceKey: "translation-tests", key: UUID().uuidString, title: "Book")
    }

    private func cache(_ pages: [Aidoku.Page], translations: [String?], manga: AidokuRunner.Manga) {
        let blocks = pages.compactMap(ReaderTextContent.load).flatMap(BookTranslationBlock.parse)
        BookTranslationCache.shared.insert(.init(source: "", target: "", blocks: blocks, translations: translations),
                                           for: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: pages[0].chapterId))
    }

    @Test func translatedFragmentsKeepPageOrderAndEscapeMarkdown() throws {
        let restore = preferences()
        defer { restore() }
        let manga = book()
        let pages = [Aidoku.Page(sourceId: manga.sourceKey, chapterId: "1", text: "First\n\n![image](file:///image.png)"),
                     Aidoku.Page(sourceId: manga.sourceKey, chapterId: "1", index: 1, text: "Second")]
        let literal = "# Literal [text](https://example.org) **words**"
        cache(pages, translations: [literal, nil, "Вторая часть"], manga: manga)
        let rendered = BookTranslationRendering.texts(pages: pages, manga: manga)
        #expect(rendered.count == 2)
        #expect(rendered[0]?.contains("![image](file:///image.png)") == true)
        let parsed = try AttributedString(markdown: try #require(rendered[0]))
        #expect(String(parsed.characters).contains(literal))
        #expect(rendered[1] == "Вторая часть")
        UserDefaults.standard.set(false, forKey: BookTranslationSettings.enabledKey)
        #expect(BookTranslationRendering.texts(pages: pages, manga: manga) == pages.map(\.text))
    }

    @Test func manualRequestBeforeChapterLoadStartsOnceContentArrives() {
        guard #available(iOS 18.0, *) else { return }
        let restore = preferences()
        defer { restore() }
        let manga = book()
        let bridge = BookTranslationBridge(source: nil, manga: manga)
        bridge.translate()
        #expect(bridge.model.job == nil)
        bridge.load(chapter: .init(key: "1"), pages: [.init(sourceId: manga.sourceKey, chapterId: "1", text: "Hello")], next: nil)
        #expect(bridge.model.job?.chapter.chapterKey == "1")
        bridge.load(chapter: .init(key: "2"), pages: [.init(sourceId: manga.sourceKey, chapterId: "2", text: "Goodbye")], next: nil)
        #expect(bridge.model.job == nil)
    }

    @Test func pagedReaderPaginatesTranslationAndLoadsTheCorrectNextChapter() async throws {
        guard #available(iOS 18.0, *) else { return }
        let restore = preferences()
        defer { restore() }
        let manga = book()
        cache([.init(sourceId: manga.sourceKey, chapterId: "1", text: "First chapter")],
              translations: [String(repeating: "Перевод первой главы. ", count: 200)], manga: manga)
        cache([.init(sourceId: manga.sourceKey, chapterId: "2", text: "Second chapter")],
              translations: [String(repeating: "Перевод второй главы. ", count: 200)], manga: manga)
        let reader = ReaderPagedTextViewController(source: nil, manga: manga)
        let progress = TranslationProgressRecorder()
        reader.delegate = progress
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = reader
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await reader.loadChapter(.init(key: "1"), startPage: 0)
        #expect(reader.hasPaginated)
        let pager = try #require(reader.children.first { $0 is UIPageViewController } as? UIPageViewController)
        let first = try #require(pager.viewControllers?.first as? TextSinglePageViewController)
        #expect(first.page.attributedContent.string.contains("Перевод первой главы"))
        reader.sliderStopped(value: 0.4)
        progress.reportedEnd = false
        cache([.init(sourceId: manga.sourceKey, chapterId: "1", text: "First chapter")],
              translations: [String(repeating: "Более короткий перевод главы. ", count: 60)], manga: manga)
        reader.translationModel?.loaded(blocks: BookTranslationBlock.parse("First chapter"), next: nil)
        #expect(progress.pageCount > 1)
        #expect(!progress.reportedEnd)
        await reader.loadChapter(.init(key: "2"), startPage: 0)
        let second = try #require(pager.viewControllers?.first as? TextSinglePageViewController)
        #expect(second.page.attributedContent.string.contains("Перевод второй главы"))
        #expect(reader.viewModel.chapter?.key == "2")
        #expect(!reader.children.contains { $0 is ReaderTranslationViewController })
    }

    @Test func scrollReaderUsesNativeScrollAndRestoresOriginalWhenDisabled() async throws {
        guard #available(iOS 18.0, *) else { return }
        let restore = preferences()
        defer { restore() }
        let manga = book()
        let original = String(repeating: "The original book paragraph. ", count: 100)
        let translation = String(repeating: "Переведённый абзац книги. ", count: 100)
        cache([.init(sourceId: manga.sourceKey, chapterId: "1", text: original)], translations: [translation], manga: manga)
        let reader = ReaderTextViewController(source: nil, manga: manga)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = reader
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await reader.loadInitialChapter(.init(key: "1"), restorePosition: false)
        let host = try #require(reader.children.compactMap { $0 as? UIHostingController<ReaderTextView> }
            .first { $0.rootView.text != nil })
        #expect(host.rootView.text?.contains("Переведённый абзац книги") == true)
        let scroll = try #require(reader.view.subviews.first { $0 is UIScrollView } as? UIScrollView)
        #expect(scroll.delegate === reader)
        UserDefaults.standard.set(false, forKey: BookTranslationSettings.enabledKey)
        NotificationCenter.default.post(name: BookTranslationSettings.changed, object: nil)
        #expect(host.rootView.text == original.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(scroll.delegate === reader)
        #expect(!reader.children.contains { $0 is ReaderTranslationViewController })
    }

    @Test func splitReaderNavigatesFromEitherPaneAndReturnsToPreviousChapterEnd() async throws {
        guard #available(iOS 18.0, *) else { return }
        let restore = preferences()
        defer { restore() }
        UserDefaults.standard.set(true, forKey: BookTranslationSettings.splitKey)
        let manga = book()
        let first = AidokuRunner.Chapter(key: "1", title: "First chapter")
        let second = AidokuRunner.Chapter(key: "2", title: "Second chapter")
        for chapter in [first, second] {
            cache([.init(sourceId: manga.sourceKey, chapterId: chapter.key, text: "Original " + chapter.key)],
                  translations: ["Translation " + chapter.key], manga: manga)
        }
        let progress = TranslationProgressRecorder()
        progress.chapters = [first, second]
        progress.chapter = first
        let reader = ReaderTranslationViewController(source: nil, manga: manga)
        reader.delegate = progress
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = reader
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        reader.beginAppearanceTransition(true, animated: false)
        reader.endAppearanceTransition()
        reader.setChapter(first, startPage: 0)

        func settle() async throws {
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(10))
                window.layoutIfNeeded()
                reader.view.layoutIfNeeded()
                for child in reader.children {
                    child.view.frame = reader.view.bounds
                    child.view.layoutIfNeeded()
                }
            }
        }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        try await settle()
        let scrolls = descendants(reader.view).compactMap { $0 as? UIScrollView }
        #expect(scrolls.count == 2)
        let upper = try #require(scrolls.first)
        let lower = try #require(scrolls.last)
        let panes = try #require(upper.delegate as? BookTranslationPanesController)

        let bottom = lower.contentSize.height - lower.bounds.height + lower.adjustedContentInset.bottom
        lower.setContentOffset(.init(x: 0, y: bottom + 80), animated: false)
        #expect(progress.chapter?.key == first.key)
        panes.scrollViewDidEndDragging(lower, willDecelerate: false)
        try await settle()
        #expect(progress.chapter?.key == second.key)
        #expect(reader.model.blocks.first?.text == "Original 2")
        #expect(abs(upper.contentOffset.y) < 1)

        upper.setContentOffset(.init(x: 0, y: -upper.adjustedContentInset.top - 80), animated: false)
        panes.scrollViewDidEndDragging(upper, willDecelerate: false)
        try await settle()
        #expect(progress.chapter?.key == first.key)
        #expect(reader.model.blocks.first?.text == "Original 1")
        #expect(upper.contentOffset.y < upper.contentSize.height)

        let nextButton = try #require(lower.subviews.compactMap { $0 as? UIButton }.first { !$0.isHidden })
        nextButton.sendActions(for: .touchUpInside)
        try await settle()
        #expect(progress.chapter?.key == second.key)
        #expect(lower.subviews.compactMap { $0 as? UIButton }.filter { !$0.isHidden }.count == 1)
        let lastBottom = lower.contentSize.height - lower.bounds.height + lower.adjustedContentInset.bottom
        lower.setContentOffset(.init(x: 0, y: lastBottom + 80), animated: false)
        panes.scrollViewDidEndDragging(lower, willDecelerate: false)
        #expect(progress.chapter?.key == second.key)
    }

    @Test func scrollingAcrossChapterGapKeepsItsPositionInBothDirections() async throws {
        guard #available(iOS 18.0, *) else { return }
        let restore = preferences()
        defer { restore() }
        let manga = book()
        let first = AidokuRunner.Chapter(key: "1", title: "First chapter")
        let second = AidokuRunner.Chapter(key: "2", title: "Second chapter")
        for chapter in [first, second] {
            let text = String(repeating: "Chapter \(chapter.key) has enough text to scroll through. ", count: 100)
            cache([.init(sourceId: manga.sourceKey, chapterId: chapter.key, text: text)], translations: [text], manga: manga)
        }
        let progress = TranslationProgressRecorder()
        progress.chapters = [first, second]
        progress.chapter = first
        let reader = ReaderTextViewController(source: nil, manga: manga)
        reader.delegate = progress
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = reader
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await reader.loadInitialChapter(first, restorePosition: false)
        window.layoutIfNeeded()
        let scroll = try #require(reader.view.subviews.first { $0 is UIScrollView } as? UIScrollView)
        let stack = try #require(scroll.subviews.first { $0 is UIStackView } as? UIStackView)
        let loadOffset = scroll.contentSize.height - scroll.bounds.height - reader.view.bounds.height / 4
        scroll.setContentOffset(.init(x: 0, y: loadOffset), animated: false)
        reader.scrollViewDidEndDecelerating(scroll)
        for _ in 0..<100 where !stack.arrangedSubviews.contains(where: { $0 is ReaderInfoPageView }) {
            await Task.yield()
        }
        window.layoutIfNeeded()
        let transition = try #require(stack.arrangedSubviews.first { $0 is ReaderInfoPageView })

        for enabled in [true, false] {
            UserDefaults.standard.set(enabled, forKey: BookTranslationSettings.enabledKey)
            NotificationCenter.default.post(name: BookTranslationSettings.changed, object: nil)
            window.layoutIfNeeded()
            let nextStart = transition.convert(transition.bounds, to: scroll).maxY
            let forward = nextStart - scroll.bounds.height / 2 + 16
            scroll.setContentOffset(.init(x: 0, y: forward), animated: false)
            #expect(progress.chapter?.key == second.key)
            #expect(abs(scroll.contentOffset.y - forward) < 1)

            let backward = nextStart - scroll.bounds.height / 2 - 16
            scroll.setContentOffset(.init(x: 0, y: backward), animated: false)
            #expect(progress.chapter?.key == first.key)
            #expect(abs(scroll.contentOffset.y - backward) < 1)
        }

        // Returning to an earlier section must not reset the loaded chapter boundaries.
        UserDefaults.standard.set(true, forKey: BookTranslationSettings.enabledKey)
        scroll.setContentOffset(.init(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        reader.scrollViewDidEndDecelerating(scroll)
        for _ in 0..<100 { await Task.yield() }
        window.layoutIfNeeded()
        #expect(stack.arrangedSubviews.filter { $0 is ReaderInfoPageView }.count == 1)
    }
}

@MainActor
private final class TranslationProgressRecorder: ReaderHoldingDelegate {
    var barsHidden = false
    var pageCount = 0
    var reportedEnd = false
    var chapters: [AidokuRunner.Chapter] = []
    var chapter: AidokuRunner.Chapter?
    func hideBars() {}
    func getNextChapter() -> AidokuRunner.Chapter? {
        guard let index = chapters.firstIndex(where: { $0.key == chapter?.key }) else { return nil }
        return chapters[safe: index + 1]
    }
    func getPreviousChapter() -> AidokuRunner.Chapter? {
        guard let index = chapters.firstIndex(where: { $0.key == chapter?.key }) else { return nil }
        return chapters[safe: index - 1]
    }
    func setChapter(_ chapter: AidokuRunner.Chapter) { self.chapter = chapter }
    func setCurrentPage(_ page: Int, position: Double?) {
        if pageCount > 1 && page >= pageCount { reportedEnd = true }
    }
    func setCurrentPages(_ pages: ClosedRange<Int>) {}
    func setPages(_ pages: [Aidoku.Page]) { pageCount = pages.count }
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() { reportedEnd = true }
}
