//
//  StringConvertible.swift
//  Aidoku
//
//  Created by skitty on 8/25/26.
//

import Foundation

protocol StringConvertible {
    init?(string: String)
    func toString() -> String
}

extension String: StringConvertible {
    init?(string: String) {
        self.init(string)
    }

    func toString() -> String {
        self
    }
}

extension URL: StringConvertible {
    func toString() -> String {
        absoluteString
    }
}
