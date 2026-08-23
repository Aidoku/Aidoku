//
//  UIKeyModifierFlags.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import UIKit

extension UIKeyModifierFlags {
    /// Command modifier, but uses shift in the simulator to avoid conflicts.
    public static var shiftOrCommand: Self {
#if targetEnvironment(simulator)
        .shift
#else
        .command
#endif
    }
}
