//
//  URLSession.swift
//  Aidoku
//
//  Created by Skitty on 12/24/21.
//

import Foundation

extension URLRequest {
    static func from(_ url: URL, headers: [String: String] = [:], method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.httpBody = body
        req.httpMethod = method
        return req
    }
}

extension URLSession {
    enum URLSessionError: Error {
        case noData
        /// The server answered, and answered with a status that is not a success.
        case httpError(statusCode: Int)
    }

    /// Downloads a request to `destination`, replacing whatever is there only once the whole body
    /// has arrived.
    ///
    /// Two properties the plain `data(for:)` form does not have. The body is streamed to disk
    /// rather than held in memory, so the size of the thing being fetched stops mattering. And the
    /// file appears at `destination` in one step, by a move within the same volume, so an
    /// interrupted or failed download leaves nothing behind for the next reader to mistake for a
    /// complete file: it is either wholly there or not there at all.
    ///
    /// A response outside the 2xx range throws before anything is written, since an error page is
    /// a body like any other and would otherwise be saved as though it were the file asked for.
    @discardableResult
    func download(for request: URLRequest, to destination: URL) async throws -> URLResponse {
        let (temporaryFile, response) = try await download(for: request)
        // The temporary file belongs to this call and is ours to clean up on every path out that
        // does not consume it.
        defer { try? FileManager.default.removeItem(at: temporaryFile) }

        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw URLSessionError.httpError(statusCode: response.statusCode)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryFile)
        } else {
            try FileManager.default.moveItem(at: temporaryFile, to: destination)
        }
        return response
    }

    func object<T: Decodable>(from url: URL) async throws -> T {
        try await self.object(from: URLRequest.from(url))
    }

    func object<T: Decodable>(from req: URLRequest) async throws -> T {
        // let start = DispatchTime.now()
        let (data, _) = try await self.data(for: req)
        // let end = DispatchTime.now()
        // print("got data (took \(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000)s)")
        let response = try JSONDecoder().decode(T.self, from: data)
        return response
    }
}
