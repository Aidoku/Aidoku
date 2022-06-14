//
//  CGRect.swift
//  Aidoku (iOS)
//
//  Created by Jim Phieffer on 6/8/22.
//

import Foundation
import UIKit

extension CGRect {
    func splitWidth(into parts: Int, index: Int = 0) -> CGRect {
        CGRect(x: minX + width / CGFloat(parts) * CGFloat(index), y: minY, width: width / CGFloat(parts), height: height)
    }
}
