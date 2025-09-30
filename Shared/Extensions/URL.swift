//
//  URL.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

extension URL {
    var queryParameters: [String: String]? {
        get {
            guard
                let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
                let queryItems = components.queryItems
            else { return nil }
            return queryItems.reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value
            }
        }
        set {
            var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
            components?.queryItems = newValue?.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
            if let url = components?.url {
                self = url
            }
        }
    }
}

extension URL {
    func toAidokuFileUrl() -> URL? {
        guard scheme == "aidoku-image" else { return nil }
        let documentsDirectory = FileManager.default.documentDirectory
        let path = host.map { $0 + self.path } ?? self.path
        return documentsDirectory.appendingPathComponent(path)
    }

    func toAidokuImageUrl() -> URL? {
        guard isFileURL else { return nil }
        // remove documents directory from the path
        let documentsDirectory = FileManager.default.documentDirectory
        guard path.hasPrefix(documentsDirectory.path) else { return nil }
        let relativePath = String(path.dropFirst(documentsDirectory.path.count))
        return URL(string: "aidoku-image://\(relativePath)")
    }
}

extension URL {
    var domain: String? {
        let host = if #available(iOS 16.0, macOS 13.0, *) {
            host(percentEncoded: false)
        } else {
            host
        }
        if let host, host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        } else {
            return host
        }
    }
}
