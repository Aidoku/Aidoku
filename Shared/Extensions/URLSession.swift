//
//  URLSession+object.swift
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
    
    func download(for request: URLRequest) async throws -> URL {
        if #available(iOS 15.0, *), #available(macOS 12.0, *) {
            let (data, _) = try await self.download(for: request, delegate: nil)
            return data
        } else {
            let data: URL = try await withCheckedThrowingContinuation({ continuation in
                self.downloadTask(with: request) { data, response, error in
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? URLSessionError.noData)
                    }
                }.resume()
            })
            return data
        }
    }
    
    func data(for request: URLRequest) async throws -> Data {
        if #available(iOS 15.0, *), #available(macOS 12.0, *) {
            let (data, _) = try await self.data(for: request, delegate: nil)
            return data
        } else {
            let data: Data = try await withCheckedThrowingContinuation({ continuation in
                self.dataTask(with: request) { data, response, error in
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? URLSessionError.noData)
                    }
                }.resume()
            })
            return data
        }
    }
    
    func object<T: Codable>(from url: URL) async throws -> T {
        return try await self.object(from: URLRequest.from(url))
    }
    
    func object<T: Codable>(from req: URLRequest) async throws -> T {
        // let start = DispatchTime.now()
        let data = try await self.data(for: req)
        // let end = DispatchTime.now()
        // print("got data (took \(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000)s)")
        let response = try JSONDecoder().decode(T.self, from: data)
        return response
    }
}
