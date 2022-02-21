//
//  UIColor.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/3/22.
//

import UIKit

extension UIColor {

    var luminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)

        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    func lighter(by percentage: CGFloat = 30) -> UIColor? {
        self.adjust(by: abs(percentage) )
    }

    func darker(by percentage: CGFloat = 30) -> UIColor? {
        self.adjust(by: -1 * abs(percentage) )
    }

    func adjust(by percentage: CGFloat = 30) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: min(red + percentage / 100, 1),
                           green: min(green + percentage / 100, 1),
                           blue: min(blue + percentage / 100, 1),
                           alpha: alpha)
        } else {
            return nil
        }
    }
}
