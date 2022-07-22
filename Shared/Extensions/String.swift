//
//  String.swift
//  Aidoku
//
//  Created by Skitty on 5/25/22.
//

import Foundation

extension String {

    func take(first: Int) -> String {
        first < count ? String(self[self.startIndex..<self.index(self.startIndex, offsetBy: first)]) : self
    }

    func take(last: Int) -> String {
        last < count ? String(self[self.index(self.endIndex, offsetBy: -last)..<self.endIndex]) : self
    }

    func drop(first: Int) -> String {
        first < count ? String(self[self.index(self.startIndex, offsetBy: first)..<self.endIndex]) : ""
    }

    func drop(last: Int) -> String {
        last < count ? String(self[self.startIndex..<self.index(self.endIndex, offsetBy: -last)]) : ""
    }

    func isoDate() -> Date? {
        ISO8601DateFormatter().date(from: self)
    }
}
