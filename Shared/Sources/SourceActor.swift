//
//  SourceActor.swift
//  Aidoku (iOS)
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

    func getFilters() async throws -> [Filter] {
        let descriptor = source.array()

        try source.vm.call("initialize_filters", descriptor)

        let filters = source.descriptors[Int(descriptor)] as? [Filter] ?? []

        source.descriptorPointer = -1
        source.descriptors = []

        return filters
    }

    func getListings() throws -> [Listing] {
        let descriptor = source.array()

        try source.vm.call("initialize_listings", descriptor)

        let listings = source.descriptors[Int(descriptor)] as? [Listing] ?? []

        source.descriptorPointer = -1
        source.descriptors = []

        return listings
    }

    func getMangaList(filters: [Filter], page: Int = 1) throws -> MangaPageResult {
        let descriptor = source.array()
        var filterPointer = -1
        if !filters.isEmpty {
            source.descriptorPointer += 1
            source.descriptors.append(filters)
            filterPointer = source.descriptorPointer
        }

        let hasMore: Int32 = try source.vm.call("manga_list_request", descriptor, Int32(filterPointer), Int32(page))

        let manga = source.descriptors[Int(descriptor)] as? [Manga] ?? []

        source.descriptorPointer = -1
        source.descriptors = []

        return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
    }

    func getMangaListing(listing: Listing, page: Int = 1) throws -> MangaPageResult {
        let descriptor = source.array()
        let listingName = source.vm.write(string: listing.name, memory: source.memory)

        let hasMore: Int32 = try source.vm.call(
            "manga_listing_request", descriptor, listingName, Int32(listing.name.count), Int32(page)
        )

        let manga = source.descriptors[Int(descriptor)] as? [Manga] ?? []

        source.memory.free(listingName)

        source.descriptorPointer = -1
        source.descriptors = []

        return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        source.descriptorPointer += 1
        source.descriptors.append(manga)

        let result: Int32 = try source.vm.call("manga_details_request", Int32(source.descriptorPointer))

        guard result >= 0, result < source.descriptors.count else { throw SourceError.mangaDetailsFailed }
        let manga = source.descriptors[Int(result)] as? Manga

        source.descriptorPointer = -1
        source.descriptors = []

        guard let manga = manga else { throw SourceError.mangaDetailsFailed }
        return manga
    }

    func getChapterList(manga: Manga) throws -> [Chapter] {
        let descriptor = source.array()
        source.descriptorPointer += 1
        source.descriptors.append(manga)

        source.chapterCounter = 0
        source.currentManga = manga.id

        try source.vm.call("chapter_list_request", descriptor, Int32(source.descriptorPointer))

        let chapters = source.descriptors[Int(descriptor)] as? [Chapter] ?? []

        source.chapterCounter = 0
        source.descriptorPointer = -1
        source.descriptors = []

        return chapters
    }

    func getPageList(chapter: Chapter) async throws -> [Page] {
        let descriptor = source.array()
        source.descriptorPointer += 1
        source.descriptors.append(chapter)

        try source.vm.call("page_list_request", descriptor, Int32(source.descriptorPointer))

        let pages = source.descriptors[Int(descriptor)] as? [Page] ?? []

        source.descriptorPointer = -1
        source.descriptors = []

        return pages
    }
}
