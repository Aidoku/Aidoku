//
//  ReadingMode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/19/22.
//

enum ReadingMode: Int {
    case rtl = 1
    case ltr = 2
    case vertical = 3
    case webtoon = 4
    case continuous = 5

    init?(_ stringValue: String) {
        switch stringValue {
            case "rtl": self = .rtl
            case "ltr": self = .ltr
            case "vertical": self = .vertical
            case "webtoon": self = .webtoon
            case "continuous": self = .continuous
            default: return nil
        }
    }
}
