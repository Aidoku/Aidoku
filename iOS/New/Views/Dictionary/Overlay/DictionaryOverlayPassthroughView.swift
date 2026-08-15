//
//  DictionaryOverlayPassthroughView.swift
//  Aidoku
//
//  Created by skitty on 7/19/26.
//

import UIKit

final class DictionaryOverlayPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
