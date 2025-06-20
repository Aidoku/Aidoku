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

//    func take(last: Int) -> String {
//        last < count ? String(self[self.index(self.endIndex, offsetBy: -last)..<self.endIndex]) : self
//    }
//
//    func drop(first: Int) -> String {
//        first < count ? String(self[self.index(self.startIndex, offsetBy: first)..<self.endIndex]) : ""
//    }
//
//    func drop(last: Int) -> String {
//        last < count ? String(self[self.startIndex..<self.index(self.endIndex, offsetBy: -last)]) : ""
//    }

    func date(format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.date(from: self)
    }

    func fuzzyMatch(_ pattern: String) -> Bool? {
        if pattern.isEmpty { return false }
        var rem = pattern[...]
        for char in self where char == rem[rem.startIndex] {
            rem.removeFirst()
            if rem.isEmpty { return true }
        }
        return false
    }
}

extension String {
    func removingExtension() -> String {
        if let idx = lastIndex(of: ".") {
            String(self[..<idx])
        } else {
            self
        }
    }
}
