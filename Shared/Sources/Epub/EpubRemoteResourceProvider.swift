//
//  EpubRemoteResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

/// Serves ePub resources from a remote endpoint.
///
/// The mapping from an ePub-internal path to a request is supplied by the caller rather than
/// encoded here, because sources address book resources differently and build their own
/// authentication. Komga exposes a `resource/` endpoint and Kavita a `book-page` one.
final actor EpubRemoteResourceProvider: EpubResourceProvider {
    /// Builds the request that fetches a given ePub-internal path, or returns nil if the source
    /// cannot address it.
    typealias RequestBuilder = @Sendable (String) -> URLRequest?

    private let buildRequest: RequestBuilder
    private let session: URLSession

    init(session: URLSession = .shared, buildRequest: @escaping RequestBuilder) {
        self.session = session
        self.buildRequest = buildRequest
    }

    /// Resolves each path against a base URL and applies a fixed set of headers.
    init(baseURL: URL, headers: [String: String] = [:], session: URLSession = .shared) {
        self.session = session
        self.buildRequest = { path in
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            return request
        }
    }

    /// An ePub-internal path with its dot segments collapsed, clamped at the root of the book.
    ///
    /// Where the path ends up pointing is decided by whatever the request builder appends it to,
    /// and nothing along that route removes a `..`: `appendingPathComponent` keeps it literally and
    /// the server resolves what arrives. A book naming `../../admin` as one of its resources would
    /// otherwise aim a request carrying the source's credentials at a path outside the book.
    ///
    /// Clamped rather than standardised, because `URL.standardized` resolves the segments against
    /// the base and so lets them leave it: the point is that a path out of a book cannot address
    /// anything the book does not contain.
    nonisolated static func confined(_ path: String) -> String {
        var components: [String] = []
        for part in path.split(separator: "/") {
            switch part {
                case ".":
                    continue
                case "..":
                    if !components.isEmpty { components.removeLast() }
                default:
                    components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    func data(at path: String) async throws -> Data {
        // Confined here rather than in either initialiser, so that a source building its own
        // requests is covered as well as the base-URL form.
        let path = Self.confined(path)
        guard let request = buildRequest(path) else {
            throw EpubResourceError.notFound(path)
        }

        let start = Date()
        let (data, response) = try await session.data(for: request)

        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw EpubResourceError.requestFailed(path: path, statusCode: response.statusCode)
        }

        // Stage 1 measured local reads only, so slice 5 has no latency baseline to plan against.
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        LogManager.logger.debug("EpubRemoteResourceProvider: fetched \(path) (\(data.count) bytes) in \(elapsed)ms")

        return data
    }
}
