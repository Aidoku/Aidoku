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
        case mangaDetailsFailed
    }

    init(source: Source) {
        self.source = source
    }

    func getMangaList(filters: [FilterBase], page: Int = 1) throws -> MangaPageResult {
        let filterDescriptor = source.globalStore.storeStdValue(filters)

        let pageResultDescriptor: Int32 = try source.vm.call("get_manga_list", filterDescriptor, Int32(page))

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(filterDescriptor)

        return result
    }

    func getMangaListing(listing: Listing, page: Int = 1) throws -> MangaPageResult {
        let listingDescriptor = source.globalStore.storeStdValue(listing)

        let pageResultDescriptor: Int32 = try source.vm.call("get_manga_listing", listingDescriptor, Int32(page))

        let result = source.globalStore.readStdValue(pageResultDescriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(pageResultDescriptor)
        source.globalStore.removeStdValue(listingDescriptor)

        return result
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        let resultMangaDescriptor: Int32 = try source.vm.call("get_manga_details", mangaDescriptor)

        let manga = source.globalStore.readStdValue(resultMangaDescriptor) as? Manga
        source.globalStore.removeStdValue(resultMangaDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        guard let manga = manga else { throw SourceError.mangaDetailsFailed }

        return manga
    }

    func getChapterList(manga: Manga) throws -> [Chapter] {
        let mangaDescriptor = source.globalStore.storeStdValue(manga)

        source.globalStore.chapterCounter = 0
        source.globalStore.currentManga = manga.id

        let chapterListDescriptor: Int32 = try source.vm.call("get_chapter_list", mangaDescriptor)

        source.globalStore.chapterCounter = 0

        let chapters = source.globalStore.readStdValue(chapterListDescriptor) as? [Chapter] ?? []
        source.globalStore.removeStdValue(chapterListDescriptor)
        source.globalStore.removeStdValue(mangaDescriptor)

        return chapters
    }

    func getPageList(chapter: Chapter) throws -> [Page] {
        let chapterDescriptor = source.globalStore.storeStdValue(chapter)

        let pageListDescriptor: Int32 = try source.vm.call("get_page_list", chapterDescriptor)

        let pages = source.globalStore.readStdValue(pageListDescriptor) as? [Page] ?? []
        source.globalStore.removeStdValue(pageListDescriptor)
        source.globalStore.removeStdValue(chapterDescriptor)

        return pages
    }

    func getImageRequest(url: String) throws -> WasmRequestObject {
        source.globalStore.requestsPointer += 1
        let request = WasmRequestObject(id: source.globalStore.requestsPointer)
        source.globalStore.requests[source.globalStore.requestsPointer] = request

        try source.vm.call("modify_image_request", Int32(request.id))

        return source.globalStore.requests[request.id] ?? request
    }

    func handleUrl(url: String) throws {
        let urlDescriptor = source.globalStore.storeStdValue(url)

        _ = try source.vm.call("handle_url", urlDescriptor) // return manga or chapter

        source.globalStore.removeStdValue(urlDescriptor)
    }

    func handleNotification(notification: String) throws {
        let notificationDescriptor = source.globalStore.storeStdValue(notification)

        try source.vm.call("handle_notification", notificationDescriptor)

        source.globalStore.removeStdValue(notificationDescriptor)
    }
}
