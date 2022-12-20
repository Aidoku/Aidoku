//
//  ReaderPageViewDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/19/22.
//

import UIKit

protocol ReaderPageViewDelegate: AnyObject {
    func imageLoaded(key: String, image: UIImage)
}
