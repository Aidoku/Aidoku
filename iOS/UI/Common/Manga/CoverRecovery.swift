//
//  CoverRecovery.swift
//  Aidoku (iOS)
//
//  Created by neldra on 5/24/26.
//

import AidokuRunner
import Foundation
import Nuke

enum CoverRecovery {
    private static let staleStatusCodes: Set<Int> = [403, 404, 410]

    // dedupes recovery so a stale cover is only refetched once per manga per session
    private actor AttemptTracker {
        private var attempted = Set<MangaIdentifier>()

        func claim(_ identifier: MangaIdentifier) -> Bool {
            attempted.insert(identifier).inserted
        }
    }

    private static let tracker = AttemptTracker()

    static func shouldRecover(from error: Error) -> Bool {
        guard
            let pipelineError = error as? ImagePipeline.Error,
            case let .dataLoadingFailed(loadingError) = pipelineError,
            let dataErr = loadingError as? DataLoader.Error,
            case let .statusCodeUnacceptable(code) = dataErr
        else { return false }
        return staleStatusCodes.contains(code)
    }

    static func recover(from error: Error, identifier: MangaIdentifier) async -> URL? {
        guard shouldRecover(from: error) else { return nil }
        guard await tracker.claim(identifier) else { return nil }
        let stub = AidokuRunner.Manga(sourceKey: identifier.sourceKey, key: identifier.mangaKey, title: "")
        guard
            let newCover = await MangaManager.shared.resetCover(manga: stub),
            let url = URL(string: newCover)
        else { return nil }
        return url
    }
}
