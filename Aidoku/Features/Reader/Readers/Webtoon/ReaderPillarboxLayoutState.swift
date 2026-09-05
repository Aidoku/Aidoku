//
//  ReaderPillarboxLayoutState.swift
//  Aidoku
//
//  Created by skitty on 9/5/26.
//

import Foundation

final class ReaderPillarboxLayoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var portrait = true

    var isPortrait: Bool {
        lock.lock()
        defer { lock.unlock() }
        return portrait
    }

    func setIsPortrait(_ isPortrait: Bool) {
        lock.lock()
        portrait = isPortrait
        lock.unlock()
    }
}
