//
//  Date.swift
//  Aidoku
//
//  Created by Skitty on 6/17/22.
//

import Foundation

extension Date {
    func ISO8601Format() -> String? {
        ISO8601DateFormatter().string(from: self)
    }

    func dateString(format: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
