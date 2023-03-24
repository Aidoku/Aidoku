//
//  BaseObservingCellNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/24/23.
//

import AsyncDisplayKit

class BaseObservingCellNode: ASCellNode {

    private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func addObserver(forName name: String, object: Any? = nil, using block: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name(name), object: object, queue: nil, using: block
        ))
    }
}
