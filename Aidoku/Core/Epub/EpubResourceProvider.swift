//
//  EpubResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

// the one boundary at which a downloaded book and a remotely served one diverge, so everything
// above it is transport-agnostic. one instance per book, per reader session
protocol EpubResourceProvider: Sendable {
    // path is epub-internal, such as OEBPS/chapter1.xhtml, rather than a url or a file path
    func data(at path: String) async throws -> Data
}

enum EpubResourceError: Error {
    case cannotOpenArchive(URL)
    case badRequest
    case notFound(String)
    case unreadable(String)
    case requestFailed(path: String, statusCode: Int)
}
