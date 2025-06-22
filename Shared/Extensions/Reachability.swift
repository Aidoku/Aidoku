//
//  Reachability.swift
//  Aidoku
//
//  Created by Skitty on 6/1/22.
//

import Foundation
import SystemConfiguration
import Network

enum NetworkDataType {
    case none
    case cellular
    case wifi
}

final class Reachability {
    private static var observers: [UUID: NWPathMonitor] = [:]
    private static let queue = DispatchQueue(label: "ReachabilityMonitorQueue")

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

    static func registerConnectionTypeObserver(
        _ handle: @escaping (NetworkDataType) -> Void,
        queue: DispatchQueue = .main
    ) -> UUID {
        let monitor = NWPathMonitor()

        monitor.pathUpdateHandler = { path in
            let connectionType: NetworkDataType
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else {
                connectionType = .none
            }
            queue.async {
                handle(connectionType)
            }
        }

        monitor.start(queue: self.queue)

        let id = UUID()
        observers[id] = monitor
        return id
    }

    static func unregisterConnectionTypeObserver(_ id: UUID) {
        observers[id]?.cancel()
        observers.removeValue(forKey: id)
    }
}
