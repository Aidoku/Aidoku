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
