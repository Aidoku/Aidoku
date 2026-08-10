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

    func data(at path: String) async throws -> Data {
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
