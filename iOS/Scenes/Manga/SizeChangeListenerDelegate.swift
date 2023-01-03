//
//  SizeChangeListenerDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/2/23.
//

import Foundation

// generic delegate for parents to listen to child view size changes

protocol SizeChangeListenerDelegate: AnyObject {
    func sizeChanged(_ newSize: CGSize)
}
