//
//  ToolbarContainerView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/24/22.
//

import UIKit

class ToolbarContainerView: UIView {

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews where subview is ReaderSliderView {
            for subsubview in subview.subviews {
                if subsubview.bounds.contains(convert(point, to: subsubview)) {
                    return subview
                }
            }
        }
        return super.hitTest(point, with: event)
    }
}
