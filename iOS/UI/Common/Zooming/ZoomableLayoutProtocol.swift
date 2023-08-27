//
//  ZoomableLayoutProtocol.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/21/22.
//

import Foundation

protocol ZoomableLayoutProtocol {
    func getScale() -> CGFloat
    func setScale(_ scale: CGFloat)
}
