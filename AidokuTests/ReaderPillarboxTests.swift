//
//  ReaderPillarboxTests.swift
//  Aidoku
//

@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
struct ReaderPillarboxTests {
    @Test(arguments: [false, true], ["landscape", "portrait", "both"])
    func followsReaderViewport(startsInPortrait: Bool, orientation: String) async {
        let temporaryPageStore = ReaderTemporaryPageStore()
        let reader = ReaderWebtoonViewController(
            source: nil,
            manga: .init(sourceKey: "test", key: "pillarbox", title: "Pillarbox"),
            temporaryPageStore: temporaryPageStore
        )
        // Create cells before the first layout, as can happen while pages are loading.
        let page = ReaderWebtoonPageNode(
            source: nil,
            page: .init(sourceId: "test", chapterId: "chapter"),
            temporaryPageStore: temporaryPageStore,
            pillarboxLayoutState: reader.pillarboxLayoutState
        )
        page.ratio = 2
        page.pillarbox = true
        page.pillarboxAmount = 20
        page.pillarboxOrientation = orientation

        let transition = ReaderWebtoonTransitionNode(
            transition: .init(type: .next, from: .init(key: "chapter"), to: nil),
            pillarboxLayoutState: reader.pillarboxLayoutState
        )
        transition.pillarbox = true
        transition.pillarboxAmount = 20
        transition.pillarboxOrientation = orientation

        // Cover initial presentation, rotation/resizing in both directions, and repeated layouts.
        for isPortrait in [startsInPortrait, !startsInPortrait, startsInPortrait, startsInPortrait] {
            let size = isPortrait ? CGSize(width: 400, height: 800) : CGSize(width: 800, height: 400)
            reader.view.bounds.size = size
            reader.viewWillLayoutSubviews()

            let shouldPillarbox = orientation == "both" || orientation == (isPortrait ? "portrait" : "landscape")
            let expectedWidth = size.width * (shouldPillarbox ? 0.8 : 1)
            #expect(reader.pillarboxLayoutState.isPortrait == isPortrait)
            #expect(page.isPillarboxOrientation() == shouldPillarbox)
            #expect(transition.isPillarboxOrientation() == shouldPillarbox)
            #expect(page.getHeight(for: size) == expectedWidth * 2)
            #expect(transition.getHeight(for: size) == expectedWidth)

            page.pillarbox = false
            transition.pillarbox = false
            #expect(page.getHeight(for: size) == size.width * 2)
            #expect(transition.getHeight(for: size) == size.width)
            page.pillarbox = true
            transition.pillarbox = true
        }

        await temporaryPageStore.removeAll()
    }
}
