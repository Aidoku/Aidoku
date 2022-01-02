//
//  Color.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import SwiftUI

extension Color {
    static var label: Color {
#if os(iOS)
        return Color(UIColor.label)
#else
        return Color(NSColor.labelColor)
#endif
    }
    
    static var secondaryLabel: Color {
#if os(iOS)
        return Color(UIColor.secondaryLabel)
#else
        return Color(NSColor.secondaryLabelColor)
#endif
    }
    
    static var secondaryFill: Color {
#if os(iOS)
        return Color(UIColor.secondarySystemFill)
#else
        return Color(NSColor.secondaryLabelColor)
#endif
    }
    
    static var tertiaryFill: Color {
#if os(iOS)
        return Color(UIColor.tertiarySystemFill)
#else
        return Color(NSColor.tertiaryLabelColor)
#endif
    }
    
    static var quaternaryFill: Color {
#if os(iOS)
        return Color(UIColor.quaternarySystemFill)
#else
        return Color(NSColor.quaternaryLabelColor)
#endif
    }
}
