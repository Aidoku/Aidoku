//
//  UIKitShim.swift
//  Aidoku
//
//  Created by Skitty on 6/7/25.
//

#if canImport(UIKit)

import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

#else

import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension NSImage {
    func pngData() -> Data? {
        guard
            let data = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: self.size)
        guard let cgImage = self.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        return cgImage
    }
}

enum UITextAutocapitalizationType: Int {
    case none = 0
    case words = 1
    case sentences = 2
    case allCharacters = 3
}

enum UIKeyboardType: Int {
    case `default` = 0
    case asciiCapable = 1
    case numbersAndPunctuation = 2
    case URL = 3
    case numberPad = 4
    case phonePad = 5
    case namePhonePad = 6
    case emailAddress = 7
    case decimalPad = 8
    case twitter = 9
    case webSearch = 10
    case asciiCapableNumberPad = 11
}

enum UIReturnKeyType: Int {
    case `default` = 0
    case go = 1
    case google = 2
    case join = 3
    case next = 4
    case route = 5
    case search = 6
    case send = 7
    case yahoo = 8
    case done = 9
    case emergencyCall = 10
    case `continue` = 11
}

#endif
