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

    func getFilters() async throws -> [Filter] {
        let descriptor = source.array()

        try source.vm.call("initialize_filters", descriptor)

        let filters = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Filter] ?? []

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return filters
    }

    func getListings() throws -> [Listing] {
        let descriptor = source.array()

        try source.vm.call("initialize_listings", descriptor)

        let listings = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Listing] ?? []

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return listings
    }

    func getMangaList(filters: [Filter], page: Int = 1) throws -> MangaPageResult {
        let descriptor = source.array()
        var filterPointer = -1
        if !filters.isEmpty {
            source.globalStore.swiftDescriptorPointer += 1
            source.globalStore.swiftDescriptors.append(filters)
            filterPointer = source.globalStore.swiftDescriptorPointer
        }

        let hasMore: Int32 = try source.vm.call("manga_list_request", descriptor, Int32(filterPointer), Int32(page))

        let manga = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Manga] ?? []

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
    }

    func getMangaListing(listing: Listing, page: Int = 1) throws -> MangaPageResult {
        let descriptor = source.array()
        let listingName = source.vm.write(string: listing.name, memory: source.memory)

        let hasMore: Int32 = try source.vm.call(
            "manga_listing_request", descriptor, listingName, Int32(listing.name.count), Int32(page)
        )

        let manga = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Manga] ?? []

        source.memory.free(listingName)

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return MangaPageResult(manga: manga, hasNextPage: hasMore > 0)
    }

    func getMangaDetails(manga: Manga) throws -> Manga {
        source.globalStore.swiftDescriptorPointer += 1
        source.globalStore.swiftDescriptors.append(manga)

        let result: Int32 = try source.vm.call("manga_details_request", Int32(source.globalStore.swiftDescriptorPointer))

        guard result >= 0, result < source.globalStore.swiftDescriptors.count else { throw SourceError.mangaDetailsFailed }
        let manga = source.globalStore.swiftDescriptors[Int(result)] as? Manga

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        guard let manga = manga else { throw SourceError.mangaDetailsFailed }
        return manga
    }

    func getChapterList(manga: Manga) throws -> [Chapter] {
        let descriptor = source.array()
        source.globalStore.swiftDescriptorPointer += 1
        source.globalStore.swiftDescriptors.append(manga)

        source.chapterCounter = 0
        source.currentManga = manga.id

        try source.vm.call("chapter_list_request", descriptor, Int32(source.globalStore.swiftDescriptorPointer))

        let chapters = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Chapter] ?? []

        source.chapterCounter = 0
        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return chapters
    }

    func getPageList(chapter: Chapter) async throws -> [Page] {
        let descriptor = source.array()
        source.globalStore.swiftDescriptorPointer += 1
        source.globalStore.swiftDescriptors.append(chapter)

        try source.vm.call("page_list_request", descriptor, Int32(source.globalStore.swiftDescriptorPointer))

        let pages = source.globalStore.swiftDescriptors[Int(descriptor)] as? [Page] ?? []

        source.globalStore.swiftDescriptorPointer = -1
        source.globalStore.swiftDescriptors = []

        return pages
    }
}
