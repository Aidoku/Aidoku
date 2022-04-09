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
        var filterPointer: Int32 = -1
        if !filters.isEmpty {
            filterPointer = source.globalStore.storeStdValue(filters)
        }

        let descriptor: Int32 = try source.vm.call("get_manga_list", filterPointer, Int32(page))

        let result = source.globalStore.readStdValue(descriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(descriptor)

        if filterPointer > -1 {
            source.globalStore.removeStdValue(filterPointer)
        }

        return result
    }

    func getMangaListing(listing: Listing, page: Int = 1) throws -> MangaPageResult {
        let listingPointer = source.globalStore.storeStdValue(listing)

        let descriptor: Int32 = try source.vm.call(
            "get_manga_listing", listingPointer, Int32(page)
        )

        let result = source.globalStore.readStdValue(descriptor) as? MangaPageResult ?? MangaPageResult(manga: [], hasNextPage: false)
        source.globalStore.removeStdValue(descriptor)
        source.globalStore.removeStdValue(listingPointer)

        return result
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        let mangaPointer = source.globalStore.storeStdValue(manga)

        let descriptor: Int32 = try source.vm.call("get_manga_details", mangaPointer)

        let manga = source.globalStore.readStdValue(descriptor) as? Manga
        source.globalStore.removeStdValue(descriptor)
        source.globalStore.removeStdValue(mangaPointer)

        guard let manga = manga else { throw SourceError.mangaDetailsFailed }

        return manga
    }

    func getChapterList(manga: Manga) throws -> [Chapter] {
        let mangaPointer = source.globalStore.storeStdValue(manga)

        source.globalStore.chapterCounter = 0
        source.globalStore.currentManga = manga.id

        let descriptor: Int32 = try source.vm.call("get_chapter_list", mangaPointer)

        source.globalStore.chapterCounter = 0

        let chapters = source.globalStore.readStdValue(descriptor) as? [Chapter] ?? []
        source.globalStore.removeStdValue(descriptor)
        source.globalStore.removeStdValue(mangaPointer)

        return chapters
    }

    func getPageList(chapter: Chapter) throws -> [Page] {
        let chapterPointer = source.globalStore.storeStdValue(chapter)

        let descriptor: Int32 = try source.vm.call("get_page_list", chapterPointer)

        let pages = source.globalStore.readStdValue(descriptor) as? [Page] ?? []
        source.globalStore.removeStdValue(descriptor)
        source.globalStore.removeStdValue(chapterPointer)

        return pages
    }

    func getImageRequest(url: String) throws -> WasmRequestObject {
        let request = WasmRequestObject(id: source.globalStore.requests.count)
        source.globalStore.requests.append(request)

        try source.vm.call("modify_image_request", Int32(request.id))

        return source.globalStore.requests[request.id]
    }

    func handleUrl(url: String) throws {
        let urlDescriptor = source.globalStore.storeStdValue(url)

        _ = try source.vm.call("handle_url", urlDescriptor) // return manga or chapter

        source.globalStore.removeStdValue(urlDescriptor)
    }
}
