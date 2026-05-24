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

    private static var attempted = Set<String>()
    private static let lock = DispatchQueue(label: "app.aidoku.coverRecovery")

    static func shouldRecover(from error: Error) -> Bool {
        guard
            let pipelineError = error as? ImagePipeline.Error,
            case let .dataLoadingFailed(loadingError) = pipelineError,
            let dataErr = loadingError as? DataLoader.Error,
            case let .statusCodeUnacceptable(code) = dataErr
        else { return false }
        return staleStatusCodes.contains(code)
    }

    static func recover(from error: Error, sourceId: String, mangaId: String) async -> URL? {
        guard shouldRecover(from: error) else { return nil }
        let key = "\(sourceId)/\(mangaId)"
        let firstAttempt = lock.sync { () -> Bool in
            guard !attempted.contains(key) else { return false }
            attempted.insert(key)
            return true
        }
        guard firstAttempt else { return nil }
        let stub = AidokuRunner.Manga(sourceKey: sourceId, key: mangaId, title: "")
        guard
            let newCover = await MangaManager.shared.resetCover(manga: stub),
            let url = URL(string: newCover)
        else { return nil }
        return url
    }
}
