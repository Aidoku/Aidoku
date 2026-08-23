//
//  iOSVersion.swift
//  Aidoku
//
//  Created by skitty on 6/9/26.
//

@_spi(Internals) @_spi(Advanced) import SwiftUIIntrospect
import UIKit

extension iOSVersion {
    public static let v27 = iOSVersion {
        #if os(iOS)
        if #available(iOS 28, *) {
            return .past
        }
        if #available(iOS 27, *) {
            return .current
        }
        return .future
        #else
        return nil
        #endif
    }
}

extension iOSViewVersion<ListType, UICollectionView> {
    public static let v27 = Self(for: .v27)
}

extension iOSViewVersion<ListCellType, UICollectionViewCell> {
    public static let v27 = Self(for: .v27)
}

extension iOSViewVersion<NavigationStackType, UINavigationController> {
    public static let v27 = Self(for: .v27)
}
