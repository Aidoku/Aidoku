//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation

class ReaderPagedViewModel {

    var pages: [Page] = []

    func loadPages(chapter: Chapter) async {
        pages = (try? await SourceManager.shared.source(for: chapter.sourceId)?.getPageList(chapter: chapter)) ?? []

//        guard !pages.isEmpty else { return } // TODO: handle zero pages
//
//        await MainActor.run {
//            let previousInfoController = ReaderPagedPageViewController(type: .info(.previous))
//            previousInfoController.currentChapter = chapter
//            self.pageViewControllers.append(previousInfoController)
//
//            for _ in 0..<pages.count {
//                self.pageViewControllers.append(ReaderPagedPageViewController(type: .page))
//            }
//
//            let nextInfoController = ReaderPagedPageViewController(type: .info(.next))
//            nextInfoController.currentChapter = chapter
//            self.pageViewControllers.append(nextInfoController)
//
//            self.pageViewControllers[1].setPage(self.pages[0])
//        }
    }
}
