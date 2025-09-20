//
//  String+Color.swift
//  Aidoku
//
//  Created by Skitty on 9/18/25.
//

import SwiftUI

extension String {
    func toColor() -> Color {
        switch lowercased() {
            case "black": return Color.black
            case "blue": return Color.blue
            case "gray", "grey": return Color.gray
            case "green": return Color.green
            case "orange": return Color.orange
            case "pink": return Color.pink
            case "purple": return Color.purple
            case "red": return Color.red
            case "white": return Color.white
            case "yellow": return Color.yellow
            case "primary": return Color.primary
            case "secondary": return Color.secondary
            default:
                // parse hex code
                var hex = if hasPrefix("#") {
                    String(dropFirst())
                } else {
                    self
                }
                if hex.count == 3 {
                    let r = hex[hex.startIndex]
                    let g = hex[hex.index(hex.startIndex, offsetBy: 1)]
                    let b = hex[hex.index(hex.startIndex, offsetBy: 2)]
                    hex = "\(r)\(r)\(g)\(g)\(b)\(b)"
                }
                if hex.count == 6, let intCode = Int(hex, radix: 16) {
                    let red = Double((intCode >> 16) & 0xFF) / 255
                    let green = Double((intCode >> 8) & 0xFF) / 255
                    let blue = Double(intCode & 0xFF) / 255
                    return Color(red: red, green: green, blue: blue)
                } else if hex.count == 8, let intCode = Int(hex, radix: 16) {
                    let red = Double((intCode >> 24) & 0xFF) / 255
                    let green = Double((intCode >> 16) & 0xFF) / 255
                    let blue = Double((intCode >> 8) & 0xFF) / 255
                    let alpha = Double(intCode & 0xFF) / 255
                    return Color(red: red, green: green, blue: blue, opacity: alpha)
                }
                return Color.black
        }
    }
}
