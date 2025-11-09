//
//  LAPolicy.swift
//  Aidoku
//
//  Created by Kyle Erhabor on 11/9/25.
//

import LocalAuthentication

extension LAPolicy {
    static let defaultPolicy = Self.deviceOwnerAuthenticationWithBiometrics
}
