//
//  Volume.swift
//  Aidoku
//
//  Created by Skitty on 1/4/22.
//

import Foundation

struct Volume: Hashable {
    let title: String
    let sortNumber: Int
    var chapters: [Chapter]
}
