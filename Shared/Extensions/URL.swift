//
//  URL.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

extension URL {
    public var queryParameters: [String: String]? {
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
