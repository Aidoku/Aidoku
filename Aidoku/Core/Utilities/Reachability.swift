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

actor Reachability {
    static let shared = Reachability()

    private var observers: [UUID: NWPathMonitor] = [:]
    private let queue = DispatchQueue(label: "ReachabilityMonitorQueue")

    nonisolated static func getConnectionType() -> NetworkDataType {
        guard let reachability = SCNetworkReachabilityCreateWithName(
            kCFAllocatorDefault,
            "www.apple.com/library/test/success.html"
        ) else {
            return .none
        }

        var flags = SCNetworkReachabilityFlags()
        let gotFlags: Bool = withUnsafeMutablePointer(to: &flags) {
            $0.withMemoryRebound(to: UInt32.self, capacity: 1) { ptr in
                SCNetworkReachabilityGetFlags(reachability, ptr)
            }
        }

        guard gotFlags, flags.contains(.reachable) else { return .none }

        return flags.contains(.isWWAN) ? .cellular : .wifi
    }

    func registerConnectionTypeObserver(
        _ handle: @escaping @MainActor @Sendable (NetworkDataType) -> Void
    ) -> UUID {
        let monitor = NWPathMonitor()
        let id = UUID()

        monitor.pathUpdateHandler = { path in
            let connectionType: NetworkDataType
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else {
                connectionType = .none
            }
            Task { @MainActor in
                handle(connectionType)
            }
        }

        observers[id] = monitor
        monitor.start(queue: self.queue)

        return id
    }

    func unregisterConnectionTypeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)?.cancel()
    }
}
