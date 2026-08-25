//
//  EpubRemoteResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

// the caller supplies the path-to-request mapping because sources address book resources
// differently and build their own authentication: komga exposes resource/, kavita book-page
final actor EpubRemoteResourceProvider: EpubResourceProvider {
    // nil where the source cannot address the path
    typealias RequestBuilder = @Sendable (String) -> URLRequest?

    private let buildRequest: RequestBuilder
    private let session: URLSession

    init(session: URLSession = .shared, buildRequest: @escaping RequestBuilder) {
        self.session = session
        self.buildRequest = buildRequest
    }

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

    // collapses dot segments and clamps at the root of the book: appendingPathComponent keeps a ..
    // literally and the server resolves what arrives, so a book naming ../../admin as a resource
    // would otherwise aim the source's credentials outside the book. clamped rather than
    // standardised, since URL.standardized resolves the segments against the base and lets them
    // leave it
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
        // confined here rather than in either initialiser, so a source building its own requests
        // is covered as well as the base-url form
        let path = Self.confined(path)
        guard let request = buildRequest(path) else {
            throw EpubResourceError.notFound(path)
        }

        let start = Date()
        let (data, response) = try await session.data(for: request)

        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw EpubResourceError.requestFailed(path: path, statusCode: response.statusCode)
        }

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        LogManager.logger.debug("EpubRemoteResourceProvider: fetched \(path) (\(data.count) bytes) in \(elapsed)ms")

        return data
    }
}
