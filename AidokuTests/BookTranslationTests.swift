import Foundation
import AidokuRunner
import Testing
import UIKit
@testable import Aidoku

@Suite struct BookTranslationTests {
    private func chapter(_ key: String, source: String = "source", book: String = "book") -> ChapterIdentifier {
        .init(sourceKey: source, mangaKey: book, chapterKey: key)
    }

    private let blocks = [BookTranslationBlock(markdown: "Hello", text: "Hello")]

    @Test @MainActor func cacheRetainsTenMostRecentlyUsedChapters() {
        let cache = BookTranslationCache()
        let entry = BookTranslationCache.Entry(source: "en", target: "ru", blocks: blocks, translations: ["Привет"])
        for index in 0..<10 { cache.insert(entry, for: chapter("\(index)")) }
        #expect(cache.count == 10)
        #expect(cache.value(for: chapter("0"), source: "en", target: "ru", blocks: blocks) != nil)
        cache.insert(entry, for: chapter("10"))
        #expect(cache.count == 10)
        #expect(cache.value(for: chapter("1"), source: "en", target: "ru", blocks: blocks) == nil)
        #expect(cache.value(for: chapter("0"), source: "en", target: "ru", blocks: blocks) == ["Привет"])
        #expect(BookTranslationCache().isEmpty)
    }

    @Test @MainActor func cacheSeparatesBooksLanguagesAndRevisedText() {
        let cache = BookTranslationCache()
        cache.insert(.init(source: "en", target: "ru", blocks: blocks, translations: ["Привет"]), for: chapter("1"))
        #expect(cache.value(for: chapter("1", book: "other"), source: "en", target: "ru", blocks: blocks) == nil)
        #expect(cache.value(for: chapter("1", source: "other"), source: "en", target: "ru", blocks: blocks) == nil)
        #expect(cache.value(for: chapter("1"), source: "fr", target: "ru", blocks: blocks) == nil)
        #expect(cache.value(for: chapter("1"), source: "en", target: "de", blocks: blocks) == nil)
        #expect(cache.value(for: chapter("1"), source: "en", target: "ru", blocks: [.init(markdown: "New", text: "New")]) == nil)
        cache.insert(.init(source: "en", target: "de", blocks: blocks, translations: ["Hallo"]), for: chapter("1"))
        #expect(cache.count == 1)
        #expect(cache.value(for: chapter("1"), source: "en", target: "de", blocks: blocks) == ["Hallo"])
    }

    @Test @MainActor func incompleteEntriesDoNotEvictValidTranslations() {
        let cache = BookTranslationCache(capacity: 1)
        cache.insert(.init(source: "", target: "", blocks: blocks, translations: ["Привет"]), for: chapter("1"))
        cache.insert(.init(source: "", target: "", blocks: blocks, translations: []), for: chapter("2"))
        #expect(cache.count == 1)
        #expect(cache.value(for: chapter("1"), source: "", target: "", blocks: blocks) != nil)
    }

    @Test func markdownKeepsImagesAndCodeOutOfTranslation() {
        let markdown = "# Heading\r\n\r\nHello **world** [link](https://example.org).\n\n![art](file:///cover.png)\n\n```swift\nlet title = \"Hello\"\n\nprint(title)\n```\n\nGoodbye"
        let result = BookTranslationBlock.parse(markdown)
        #expect(result.count == 5)
        #expect(result[0].text == "Heading")
        #expect(result[1].text == "Hello world link.")
        #expect(result[2].text == nil)
        #expect(result[2].markdown == "![art](file:///cover.png)")
        #expect(result[3].text == nil)
        #expect(result[3].markdown.contains("\n\nprint"))
        #expect(result[4].text == "Goodbye")
        #expect(BookTranslationBlock.parse("\n \n").isEmpty)
    }

    @Test func chunkingPreservesUnicodeAndEveryCharacter() {
        for text in [String(repeating: "Hello 👨‍👩‍👧‍👦! Привет мир. ", count: 1000), String(repeating: "漢", count: 8000)] {
            let chunks = BookTranslationBlock.chunks(text)
            #expect(chunks.count > 1)
            #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 3000 })
            #expect(chunks.joined() == text)
        }
    }

    @Test func scrollingAlignsParagraphsDespiteDifferentLengths() {
        let anchor = BookTranslationScrollPosition.anchor(offset: 150, starts: [0, 100, 300], heights: [100, 200, 50])
        #expect(anchor == 1.25)
        let target = BookTranslationScrollPosition.offset(anchor: anchor, starts: [0, 200, 600], heights: [200, 400, 100])
        #expect(target == 300)
        #expect(BookTranslationScrollPosition.anchor(offset: target, starts: [0, 200, 600], heights: [200, 400, 100]) == anchor)
        #expect(BookTranslationScrollPosition.anchor(offset: -50, starts: [0], heights: [100]) == 0)
        #expect(BookTranslationScrollPosition.offset(anchor: 100, starts: [0, 100], heights: [100, 200]) == 300)
        #expect(BookTranslationScrollPosition.offset(anchor: .nan, starts: [0], heights: [100]) == 0)
    }

    @Test @MainActor func manualTranslationWaitsForLoadingAndDoesNotCarryIntoAnotherChapter() throws {
        guard #available(iOS 18.0, *) else { return }
        let suite = "BookTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BookTranslationModel(source: nil, manga: .init(sourceKey: "source", key: "book", title: "Book"),
                                         defaults: defaults, cache: BookTranslationCache())
        model.reset(chapter: .init(key: "1"))
        model.translate()
        #expect(model.job == nil)
        model.loaded(blocks: blocks, next: nil)
        #expect(model.job?.chapter == chapter("1"))
        model.reset(chapter: .init(key: "2"))
        model.loaded(blocks: blocks, next: nil)
        #expect(model.job == nil)
        #expect(model.translations == nil)
        model.reset(chapter: .init(key: "3"))
        model.translate()
        model.cancel()
        model.loaded(blocks: blocks, next: nil)
        #expect(model.job == nil)
    }

    @Test @MainActor func automaticTranslationAndLanguageChangesUseFreshJobs() throws {
        guard #available(iOS 18.0, *) else { return }
        let suite = "BookTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BookTranslationSettings.automaticKey)
        let cache = BookTranslationCache()
        cache.insert(.init(source: "", target: "", blocks: blocks, translations: ["Привет"]), for: chapter("1"))
        let model = BookTranslationModel(source: nil, manga: .init(sourceKey: "source", key: "book", title: "Book"),
                                         defaults: defaults, cache: cache)
        #expect(model.cachedBlocks(for: .init(key: "1")) == blocks)
        model.reset(chapter: .init(key: "1"))
        model.loaded(blocks: blocks, next: nil)
        #expect(model.translations == ["Привет"])
        #expect(model.job == nil)
        defaults.set("de", forKey: BookTranslationSettings.targetKey)
        model.updateSettings()
        #expect(model.cachedBlocks(for: .init(key: "1")) == nil)
        #expect(model.translations == nil)
        #expect(model.job?.settings.target == "de")
        model.reset(chapter: .init(key: "2"))
        model.loaded(blocks: blocks, next: nil)
        #expect(model.job?.chapter == chapter("2"))
        #expect(model.job?.isAhead == false)
        model.cancel()
    }

    @Test @MainActor func lateChapterListUsesPretranslatedNextChapterWithoutFetching() throws {
        guard #available(iOS 18.0, *) else { return }
        let suite = "BookTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BookTranslationSettings.aheadKey)
        let cache = BookTranslationCache()
        let entry = BookTranslationCache.Entry(source: "", target: "", blocks: blocks, translations: ["Привет"])
        cache.insert(entry, for: chapter("1"))
        cache.insert(entry, for: chapter("2"))
        let model = BookTranslationModel(source: nil, manga: .init(sourceKey: "source", key: "book", title: "Book"),
                                         defaults: defaults, cache: cache)
        model.reset(chapter: .init(key: "1"))
        model.loaded(blocks: blocks, next: nil)
        model.updateNextChapter(.init(key: "2"))
        #expect(model.status == NSLocalizedString("TRANSLATION_NEXT_READY"))
        #expect(model.job == nil)
        #expect(model.translations == ["Привет"])
        model.updateNextChapter(nil)
        #expect(model.status == nil)
        #expect(model.job == nil)
        #expect(model.translations == ["Привет"])
    }

    @Test @MainActor func actualPanesScrollBothWaysAndPreservePositionAfterLayoutChanges() throws {
        guard #available(iOS 18.0, *) else { return }
        let controller = BookTranslationPanesController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let blocks = BookTranslationBlock.parse("# Chapter One\n\n" + String(repeating: "The garden was quiet that morning. ", count: 30)
            + "\n\n" + String(repeating: "She opened the old wooden door. ", count: 20))
        let translations: [String?] = ["Глава первая", String(repeating: "В то утро в саду было тихо. ", count: 55),
                                       String(repeating: "Она открыла старую деревянную дверь. ", count: 25)]
        controller.update(blocks: blocks, translations: translations, appearance: .init(split: true, revision: 0),
                          position: 0, positionRevision: 0)
        window.layoutIfNeeded()

        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let scrolls = descendants(controller.view).compactMap { $0 as? UIScrollView }
        #expect(scrolls.count == 2)
        let upper = try #require(scrolls.first)
        let lower = try #require(scrolls.last)
        let upperStack = try #require(upper.subviews.first { $0 is UIStackView } as? UIStackView)
        let lowerStack = try #require(lower.subviews.first { $0 is UIStackView } as? UIStackView)
        #expect(upper.frame.height > 200)
        #expect(abs(upper.frame.height - lower.frame.height) < 1)

        func offset(_ stack: UIStackView, anchor: Double) -> CGFloat {
            BookTranslationScrollPosition.offset(anchor: anchor, starts: stack.arrangedSubviews.map(\.frame.minY),
                                                 heights: stack.arrangedSubviews.map(\.frame.height))
        }
        upper.setContentOffset(.init(x: 0, y: offset(upperStack, anchor: 1.25)), animated: false)
        #expect(abs(lower.contentOffset.y - offset(lowerStack, anchor: 1.25)) < 1)
        lower.setContentOffset(.init(x: 0, y: offset(lowerStack, anchor: 1.5)), animated: false)
        #expect(abs(upper.contentOffset.y - offset(upperStack, anchor: 1.5)) < 1)

        controller.update(blocks: blocks, translations: translations, appearance: .init(split: false, revision: 0),
                          position: 0, positionRevision: 0)
        controller.update(blocks: blocks, translations: translations, appearance: .init(split: true, revision: 1),
                          position: 0, positionRevision: 0)
        window.layoutIfNeeded()
        #expect(abs(upper.contentOffset.y - offset(upperStack, anchor: 1.5)) < 1)
        #expect(abs(lower.contentOffset.y - offset(lowerStack, anchor: 1.5)) < 1)
    }
}
