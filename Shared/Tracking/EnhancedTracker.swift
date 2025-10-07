//
//  EnhancedTracker.swift
//  Aidoku
//
//  Created by Skitty on 9/15/25.
//

/// A tracker that automatically registers and tracks supported series.
protocol EnhancedTracker: Tracker {}

extension EnhancedTracker {
    var isLoggedIn: Bool { true }

    func search(title: String, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        fatalError("search by title not implemented for enhanced tracker")
    }

    func logout() {
        fatalError("logout not implement for enanced tracker")
    }
}
