//
//  Collection.swift
//  Aidoku
//
//  Created by Jim Phieffer on 5/14/22.
//
//  Credit to Nikita Kukushkin for this
//  https://stackoverflow.com/questions/25329186/safe-bounds-checked-array-lookup-in-swift-through-optional-bindings
//

import Foundation

extension Collection {
    subscript (safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
