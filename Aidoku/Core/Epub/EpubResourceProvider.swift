//
//  EpubResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

// the one boundary at which a downloaded book and a remote one diverge
protocol EpubResourceProvider: Sendable {
    func data(at path: String) async throws -> Data
}

enum EpubResourceError: Error {
    case cannotOpenArchive(URL)
    case badRequest
    case notFound(String)
    case unreadable(String)
    case requestFailed(path: String, statusCode: Int)
}
