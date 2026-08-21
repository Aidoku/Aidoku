//
//  TestableSource.swift
//  Aidoku
//
//  Created by skitty on 8/21/26.
//

import AidokuRunner
import Foundation

extension AidokuRunner.Source {
    static func test(runner: TestableSourceRunner) -> AidokuRunner.Source {
        .init(
            url: nil,
            key: "test",
            name: "Test",
            version: 1,
            languages: ["multi"],
            contentRating: .safe,
            runner: runner
        )
    }
}

actor TestableSourceStorage {
    var nextDescriptor: Int32 = 0
    var processedContexts: [PageContext?] = []

    func getContexts() -> [PageContext?] {
        processedContexts
    }

    func process(_ context: PageContext?) {
        processedContexts.append(context)
    }

    func store() -> Int32 {
        nextDescriptor += 1
        return nextDescriptor
    }
}

final class TestableSourceRunner: AidokuRunner.Runner {
    let features: AidokuRunner.SourceFeatures = .init(processesPages: true)

    let storage = TestableSourceStorage()

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: [], hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        []
    }

    func processPageImage(response: Response, context: PageContext?) async throws -> PlatformImage? {
        await storage.process(context)
        return nil
    }

    func store<T: Sendable>(value _: T) async throws -> Int32 {
        await storage.store()
    }

    func remove(value _: Int32) async throws {
    }
}
