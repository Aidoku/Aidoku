//
//  Date.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

extension Date {
    func dateString(format: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}

// for komga extension
extension Date {
//    var year: Int {
//        Calendar.current.component(.year, from: self)
//    }

    static func firstOf(year: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))
    }

    static func lastOf(year: Int) -> Date? {
        if let firstOfNextYear = Calendar.current.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
            return Calendar.current.date(byAdding: .day, value: -1, to: firstOfNextYear)
        }
        return nil
    }
}
