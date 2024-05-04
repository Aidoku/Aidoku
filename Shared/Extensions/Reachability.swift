//
//  Reachability.swift
//  Aidoku
//
//  Created by Skitty on 6/1/22.
//

import Foundation
import SystemConfiguration
import CoreTelephony

enum NetworkDataType {
    case none
    case cellular
    case wifi
}

class Reachability {
    static func getConnectionType() -> NetworkDataType {
        guard let reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, "www.apple.com/library/test/success.html") else {
            return .none
        }

        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)

        guard flags.contains(.reachable) else { return .none }

        #if os(OSX)
            return .wifi
        #else
            return flags.contains(.isWWAN) ? .cellular : .wifi
        #endif
    }
}
