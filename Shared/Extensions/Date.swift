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
}
