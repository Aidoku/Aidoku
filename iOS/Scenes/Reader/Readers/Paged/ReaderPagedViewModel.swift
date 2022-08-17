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
    }
}
