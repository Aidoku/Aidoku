//
//  SourceActor.swift
//  Aidoku
//
//  Created by Skitty on 2/21/22.
//

import Foundation

actor SourceActor {

    var source: Source

    enum SourceError: Error {
        case vmNotLoaded
        case missingValue
    }

    init(source: Source) {
        self.source = source
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) async throws -> MangaPageResult {
        let filterDescriptor = source.globalStore.storeStdValue(filters)

        let pageResultDescriptor: Int32 = await source.globalStore.call("get_manga_list", args: [filterDescriptor, Int32(page)]) ?? -1

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(filterDescriptor)

        return result
    }

    func getMangaListing(listing: Listing, page: Int = 1) async throws -> MangaPageResult {
        let listingDescriptor = source.globalStore.storeStdValue(listing)

        let pageResultDescriptor: Int32 = await source.globalStore.call("get_manga_listing", args: [listingDescriptor, Int32(page)]) ?? -1

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(listingDescriptor)

        return result
    }

    func getMangaDetails(manga: Manga) async throws -> Manga {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        let resultMangaDescriptor: Int32 = await source.globalStore.call("get_manga_details", args: [mangaDescriptor]) ?? -1

        let manga = source.globalStore.readStdValue(resultMangaDescriptor) as? Manga
        source.globalStore.removeStdValue(resultMangaDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        guard let manga = manga else { throw SourceError.missingValue }

        return manga
    }

    func getChapterList(manga: Manga) async throws -> [Chapter] {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        source.globalStore.chapterCounter = 0
        source.globalStore.currentManga = manga.id

        let chapterListDescriptor: Int32 = await source.globalStore.call("get_chapter_list", args: [mangaDescriptor]) ?? -1

        source.globalStore.chapterCounter = 0

        let chapters = source.globalStore.readStdValue(chapterListDescriptor) as? [Chapter] ?? []
        source.globalStore.removeStdValue(chapterListDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        return chapters
    }

    func getPageList(chapter: Chapter) async throws -> [Page] {
        let chapterDescriptor = source.globalStore.storeStdValue(chapter)

        let pageListDescriptor: Int32 = await source.globalStore.call("get_page_list", args: [chapterDescriptor]) ?? -1

        let pages = source.globalStore.readStdValue(pageListDescriptor) as? [Page] ?? []
        source.globalStore.removeStdValue(pageListDescriptor)
        source.globalStore.removeStdValue(chapterDescriptor)

        return pages
    }

    func getImageRequest(url: String) async throws -> WasmRequestObject {
        source.globalStore.requestsPointer += 1
        let request = WasmRequestObject(id: source.globalStore.requestsPointer)
        source.globalStore.requests[source.globalStore.requestsPointer] = request

        _ = await source.globalStore.call("modify_image_request", args: [Int32(request.id)])

        return source.globalStore.requests[request.id] ?? request
    }

    func handleUrl(url: String) async throws -> DeepLink {
        let urlDescriptor = source.globalStore.storeStdValue(url)

        let deepLinkDescriptor: Int32 = await source.globalStore.call("handle_url", args: [urlDescriptor]) ?? -1

        let deepLink = source.globalStore.readStdValue(deepLinkDescriptor) as? DeepLink
        source.globalStore.removeStdValue(deepLinkDescriptor)
        source.globalStore.removeStdValue(urlDescriptor)

        guard let deepLink = deepLink else { throw SourceError.missingValue }

        return deepLink
    }

    func handleNotification(notification: String) async throws {
        let notificationDescriptor = source.globalStore.storeStdValue(notification)

        _ = await source.globalStore.call("handle_notification", args: [notificationDescriptor])

        source.globalStore.removeStdValue(notificationDescriptor)
    }
}
