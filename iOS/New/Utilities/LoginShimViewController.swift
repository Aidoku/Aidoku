//
//  LoginShimViewController.swift
//  Aidoku
//
//  Created by Skitty on 9/20/25.
//

import AuthenticationServices

#if os(macOS)

import AppKit

class LoginShimViewController: NSViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

#else

import UIKit

class LoginShimViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

#endif
