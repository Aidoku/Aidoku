//
//  Dates.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 13/02/2024.
//

import Foundation

extension Date {
    static func makeRelativeDate(days: Int) -> String {
        let now = Date()
        let date = now.addingTimeInterval(-86400 * Double(days))
        let difference = Calendar.autoupdatingCurrent.dateComponents(Set([Calendar.Component.day]), from: date, to: now)

        // today or yesterday
        if days < 2 {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        } else if days < 8 { // n days ago
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
