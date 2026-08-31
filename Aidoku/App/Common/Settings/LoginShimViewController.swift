//
//  LoginShimViewController.swift
//  Aidoku
//
//  Created by Skitty on 9/20/25.
//

import AuthenticationServices
import UIKit

class LoginShimViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
