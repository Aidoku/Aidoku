//
//  LocalSource.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import AidokuRunner
import Foundation

extension AidokuRunner.Source {
    static func local() -> AidokuRunner.Source {
        .init(
            url: nil,
            key: LocalSourceRunner.sourceKey,
            name: NSLocalizedString("LOCAL_FILES"),
            version: 1,
            languages: ["multi"],
            urls: [],
            contentRating: .safe,
            config: .init(
                languageSelectType: .single
            ),
            staticListings: [],
            staticFilters: [],
            staticSettings: [],
            runner: LocalSourceRunner()
        )
    }
}

final class LocalSourceRunner: AidokuRunner.Runner {
    static let sourceKey = "local"

    let features = AidokuRunner.SourceFeatures(
        providesListings: true,
        providesHome: false, // todo
        dynamicFilters: false,
        dynamicSettings: false,
        dynamicListings: false,
        processesPages: false,
        providesImageRequests: false,
        providesPageDescriptions: false,
        providesAlternateCovers: false,
        providesBaseUrl: false,
        handlesNotifications: false,
        handlesDeepLinks: false,
        handlesBasicLogin: false,
        handlesWebLogin: false
    )

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        await LocalFileManager.shared.scanLocalFiles()
        let manga = await LocalFileDataManager.shared.fetchLocalSeries(query: query)
        return .init(entries: manga, hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        var manga = manga
        if needsDetails {}
        if needsChapters {
            manga.chapters = await LocalFileDataManager.shared.fetchChapters(mangaId: manga.key)
        }
        return manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        await LocalFileManager.shared.fetchPages(mangaId: manga.key, chapterId: chapter.key)
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        let manga = await LocalFileDataManager.shared.fetchLocalSeries()
        return .init(entries: manga, hasNextPage: false)
    }
}
