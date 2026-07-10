//
//  SuwayomiSetupView.swift
//  Aidoku
//
//  Created by skitty on 7/5/26.
//

import SwiftUI

struct SuwayomiSetupView: View {
    private struct LoginCheck {
        let cookie: String?
        let accessToken: String?
        let refreshToken: String?
    }

    var body: some View {
        SelfHostedSourceSetupView(
            icon: Image(.suwayomi),
            title: NSLocalizedString("SUWAYOMI_SETUP"),
            sourceName: NSLocalizedString("SUWAYOMI"),
            info: NSLocalizedString("SUWAYOMI_INFO"),
            learnMoreUrl: URL(string: "https://github.com/Suwayomi/Suwayomi-Server"),
            sourceKeyPrefix: SuwayomiSourceRunner.sourceKeyPrefix,
            useEmail: false,
            placeholderServer: "http://127.0.0.1:4567",
            checkServer: check(server:),
            logIn: logIn(name:server:username:password:),
            noLogIn: noLogIn
        )
    }

    private func check(server: String) async -> ServerCheck {
        guard
            let serverUrl = URL(string: server),
            let loginType = await SuwayomiHelper.getLoginType(server: serverUrl)
        else {
            return ServerCheck()
        }

        return switch loginType {
            case .none:
                ServerCheck(canSkipLogin: true)
            case .basic, .simple, .ui:
                ServerCheck(canLoginBasic: true)
        }
    }

    private func noLogIn(name: String, server: URL) async -> Bool {
        _ = await SourceManager.shared.createCustomSource(
            kind: .suwayomi,
            name: name,
            server: server
        )
        return true
    }

    private func logIn(name: String, server: URL, username: String, password: String) async -> Bool {
        guard let response = await SuwayomiHelper.checkLogin(server: server, username: username, password: password) else {
            return false
        }

        let key = await SourceManager.shared.createCustomSource(
            kind: .suwayomi,
            name: name,
            server: server,
            username: username,
            password: password
        )

        if let cookie = response.cookie {
            UserDefaults.standard.setValue(cookie, forKey: "\(key).cookie")
        }
        if let accessToken = response.accessToken, let refreshToken = response.refreshToken {
            UserDefaults.standard.setValue(accessToken, forKey: "\(key).token")
            UserDefaults.standard.setValue(refreshToken, forKey: "\(key).refreshToken")
        }

        return true
    }
}
