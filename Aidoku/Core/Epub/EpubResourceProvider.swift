//
//  EpubResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

/// Supplies the bytes of a resource stored inside an ePub.
///
/// Paths are always ePub-internal, such as `OEBPS/chapter1.xhtml`, rather than URLs or filesystem
/// paths. This is the single boundary at which a downloaded book and a book served by a remote
/// source diverge, so everything above it is transport-agnostic. A provider instance corresponds
/// to one book for the duration of one reader session.
protocol EpubResourceProvider: Sendable {
    /// Returns the bytes for a path relative to the ePub root.
    func data(at path: String) async throws -> Data
}

enum EpubResourceError: Error {
    /// The archive could not be opened.
    case cannotOpenArchive(URL)
    /// The request carried no usable path.
    case badRequest
    /// No resource exists at the given path.
    case notFound(String)
    /// The resource exists but could not be read.
    case unreadable(String)
    /// The server refused the request.
    case requestFailed(path: String, statusCode: Int)
}
