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

extension Date {
    static func makeRelativeDate(days: Int) -> String {
        let now = Date()
        let date = now.addingTimeInterval(-86400 * Double(days))
        let difference = Calendar.autoupdatingCurrent.dateComponents(Set([Calendar.Component.day]), from: date, to: now)

        // today or yesterday
        if days <= 1 {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        } else if days <= 7 { // n days ago
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .short
            formatter.allowedUnits = .day
            guard let timePhrase = formatter.string(from: difference) else { return "" }
            return String(format: NSLocalizedString("%@_AGO", comment: ""), timePhrase)
        } else { // mm/dd/yy
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

extension Date {
    static func endOfDay() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: start)!
    }

    static func startOfDay() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.startOfDay(for: Date())
    }
}
