//
//  LogType.swift
//  Aidoku
//
//  Created by Skitty on 11/17/25.
//

enum LogType {
    case `default`
    case info
    case debug
    case warning
    case error

    func toString() -> String {
        switch self {
            case .default: ""
            case .info: "INFO"
            case .debug: "DEBUG"
            case .warning: "WARN"
            case .error: "ERROR"
        }
    }
}
