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
        case httpError(statusCode: Int)
    }

    // streams the body to disk instead of holding it in memory, and appears at destination in one
    // move, so an interrupted download leaves nothing for the next reader to mistake for a complete
    // file. a non-2xx response throws before anything is written, since an error page is a body too
    @discardableResult
    func download(for request: URLRequest, to destination: URL) async throws -> URLResponse {
        let (temporaryFile, response) = try await download(for: request)
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

extension URLSession {
    static func withTimeoutInterval(_ interval: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }
}
