//
//  TapZone.swift
//  Aidoku
//
//  Created by Skitty on 6/26/25.
//

import Foundation

struct TapZone {
    enum RegionType {
        case left
        case right
    }

    struct Region {
        // bounds in relative coordinates (0-1)
        let bounds: CGRect
        let type: RegionType
    }

    let regions: [Region]

    // reference: https://github.com/mihonapp/mihon/tree/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/navigation
    static let leftRight = TapZone(
        regions: [
            Region(bounds: CGRect(x: CGFloat(0), y: 0, width: 1/3, height: 1), type: .left),
            Region(bounds: CGRect(x: CGFloat(2)/3, y: 0, width: 1/3, height: 1), type: .right)
        ]
    )

    static let lShaped = TapZone(
        regions: [
            Region(bounds: CGRect(x: CGFloat(0), y: 1/3, width: 1/3, height: 1/3), type: .left),
            Region(bounds: CGRect(x: CGFloat(0), y: 0, width: 1, height: 1/3), type: .left),
            Region(bounds: CGRect(x: CGFloat(2)/3, y: 1/3, width: 1/3, height: 2/3), type: .right),
            Region(bounds: CGRect(x: CGFloat(0), y: 2/3, width: 2/3, height: 1/3), type: .right)
        ]
    )

    static let kindle = TapZone(
        regions: [
            Region(bounds: CGRect(x: CGFloat(0), y: 1/3, width: 1/3, height: 2/3), type: .left),
            Region(bounds: CGRect(x: CGFloat(1)/3, y: 1/3, width: 2/3, height: 2/3), type: .right)
        ]
    )

    static let edge = TapZone(
        regions: [
            Region(bounds: CGRect(x: CGFloat(0), y: 0, width: 1/3, height: 1), type: .right),
            Region(bounds: CGRect(x: CGFloat(1)/3, y: 2/3, width: 1/3, height: 1/3), type: .left),
            Region(bounds: CGRect(x: CGFloat(2)/3, y: 0, width: 1/3, height: 1), type: .right)
        ]
    )
}

enum DefaultTapZones: String, CaseIterable {
    case automatic = "auto"
    case leftRight = "left-right"
    case lShaped = "l-shaped"
    case kindle = "kindle"
    case edge = "edge"
    case disabled = "disabled"

    var value: String {
        rawValue
    }

    var tapZone: TapZone? {
        switch self {
            case .automatic: nil
            case .leftRight: .leftRight
            case .lShaped: .lShaped
            case .kindle: .kindle
            case .edge: .edge
            case .disabled: nil
        }
    }

    var title: String {
        switch self {
            case .automatic: NSLocalizedString("AUTOMATIC")
            case .leftRight: NSLocalizedString("ZONE_LEFT_RIGHT")
            case .lShaped: NSLocalizedString("ZONE_L_SHAPED")
            case .kindle: NSLocalizedString("ZONE_KINDLE")
            case .edge: NSLocalizedString("ZONE_EDGE")
            case .disabled: NSLocalizedString("DISABLED")
        }
    }
}
