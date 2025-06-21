//
//  LegacySource.swift
//  Aidoku
//
//  Created by Skitty on 11/1/23.
//

import Foundation
import AidokuRunner

extension AidokuRunner.Source {
    var legacySource: Source? {
        (runner as? LegacySourceRunner)?.source
    }

    static func legacy(source: Source) -> AidokuRunner.Source {
        AidokuRunner.Source(
            url: source.url,
            key: source.id,
            name: source.manifest.info.name,
            version: source.manifest.info.version,
            languages: source.languages.isEmpty ? [source.manifest.info.lang] : source.languages.map { $0.code },
            urls: (source.manifest.info.urls ?? [source.manifest.info.url ?? ""]).compactMap { URL(string: $0) },
            contentRating: AidokuRunner.SourceContentRating(rawValue: source.manifest.info.nsfw ?? 0) ?? .safe,
            imageUrl: source.url.appendingPathComponent("Icon.png"),
            config: .init(
                languageSelectType: source.manifest.languageSelectType == "single" ? .single : .multiple
            ),
            staticListings: source.listings.map { AidokuRunner.Listing(id: $0.name, name: $0.name) },
            staticFilters: [],
            runner: LegacySourceRunner(source: source)
        )
    }
}

final class LegacySourceRunner: AidokuRunner.Runner {
    let source: Source

    let features: SourceFeatures

    init(source: Source) {
        self.source = source
        self.features = .init(
            providesListings: true,
            providesHome: false,
            dynamicFilters: false,
            dynamicSettings: false,
            dynamicListings: false,
            processesPages: false,
            providesImageRequests: source.handlesImageRequests,
            providesPageDescriptions: false,
            providesAlternateCovers: false,
            providesBaseUrl: false,
            handlesNotifications: true,
            handlesDeepLinks: true
        )
    }

    func getHome() async throws -> AidokuRunner.Home {
        throw AidokuRunner.SourceError.unimplemented
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        try await source.getMangaListing(listing: Listing(name: listing.name), page: page).toNew()
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        let filters: [FilterBase]
        if let query {
            filters = [TitleFilter(value: query)]
        } else {
            filters = []
        }
        let result = try await source.getMangaList(filters: filters, page: page)
        return result.toNew()
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        let newManga = try await source.getMangaDetails(manga: Manga(sourceId: source.id, id: manga.key))
        var result = newManga.toNew()
        if needsChapters {
            let chapters = try await source.getChapterList(manga: newManga)
            result.chapters = chapters.map { $0.toNew() }
        }
        return result
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        let result = try await source.getPageList(
            chapter: Chapter(
                sourceId: manga.sourceKey,
                id: chapter.key,
                mangaId: manga.key,
                title: chapter.title,
                sourceOrder: 0
            )
        )
        return result.map { $0.toNew() }
    }

    func getImageRequest(url: String, context _: AidokuRunner.PageContext?) async throws -> URLRequest {
        let sourceImageRequest = try await source.getImageRequest(url: url)
        guard
            let urlString = sourceImageRequest.url,
            let url = URL(string: urlString)
        else {
            throw SourceError.missingResult
        }
        var request = URLRequest(url: url)
        for (key, value) in sourceImageRequest.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = sourceImageRequest.body {
            request.httpBody = body
        }
        return request
    }

    func handleDeepLink(url: String) async throws -> DeepLinkResult? {
        let result = try await source.handleUrl(url: url)
        guard let mangaId = result.manga?.id else { return nil }
        return DeepLinkResult(
            mangaKey: mangaId,
            chapterKey: result.chapter?.id
        )
    }

    func handleNotification(notification: String) async throws {
        await source.actor.handleNotification(notification: notification)
    }
}
