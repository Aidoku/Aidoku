//
//  KavitaSetupView.swift
//  Aidoku
//
//  Created by skitty on 7/5/26.
//

import SwiftUI

struct KavitaSetupView: View {
    static let demoServer = "https://demo.kavitareader.com"

    var body: some View {
        SelfHostedSourceSetupView(
            icon: Image(.kavita),
            title: NSLocalizedString("KAVITA_SETUP"),
            sourceName: NSLocalizedString("KAVITA"),
            info: NSLocalizedString("KAVITA_INFO"),
            learnMoreUrl: URL(string: "https://wiki.kavitareader.com/getting-started/"),
            sourceKeyPrefix: KavitaSourceRunner.sourceKeyPrefix,
            useEmail: false,
            demoServer: Self.demoServer,
            demoTitle: NSLocalizedString("DEMO_KAVITA_SERVER"),
            demoInfo: NSLocalizedString("DEMO_KAVITA_SERVER_INFO"),
            checkServer: check(server:),
            logIn: logIn(name:server:username:password:),
            apiKeyLogIn: logIn(name:server:apiKey:),
            oidcLogIn: logIn(name:server:cookies:)
        )
    }

    private func check(server: String) async -> ServerCheck {
        // ensure url is valid (shouldn't fail)
        guard
            let testUrl = URL(string: server + "/api/admin/exists"),
            let oidcCheckUrl = URL(string: server + "/api/settings/oidc")
        else {
            return ServerCheck(canLoginBasic: false)
        }

        // ensure we can reach kavita api from server
        let check: Bool? = try? await URLSession.shared.object(from: testUrl)
        guard check == true else {
            return ServerCheck(canLoginBasic: false)
        }

        let canLoginApiKey = server != Self.demoServer // disable api key login for demo server since it isn't accessible

        struct OIDCResponse: Decodable {
            let disablePasswordAuthentication: Bool
            let enabled: Bool
            let providerName: String
        }
        let response: OIDCResponse? = try? await URLSession.shared.object(from: oidcCheckUrl)
        if let response {
            return ServerCheck(
                canLoginBasic: !response.disablePasswordAuthentication,
                canLoginApiKey: canLoginApiKey,
                canLoginOIDC: response.enabled,
                oidcLoginURL: URL(string: server + "/oidc/login?returnURL=aidoku://oidc-auth")
            )
        }

        return ServerCheck(
            canLoginBasic: true,
            canLoginApiKey: canLoginApiKey,
            canLoginOIDC: false,
            oidcLoginURL: nil
        )
    }

    private func logIn(name: String, server: URL, username: String, password: String) async -> Bool {
        let response = await KavitaSourceRunner.getLoginResponse(server: server, username: username, password: password)

        guard
            let response,
            let token = response.token,
            let refreshToken = response.refreshToken,
            let apiKey = response.getApiKey(),
            response.username == username
        else {
            return false
        }

        let key = await SourceManager.shared.createCustomSource(
            kind: .kavita,
            name: name,
            server: server,
            username: username,
            password: password
        )

        UserDefaults.standard.setValue(apiKey, forKey: "\(key).apiKey")
        UserDefaults.standard.setValue(token, forKey: "\(key).token")
        UserDefaults.standard.setValue(refreshToken, forKey: "\(key).refreshToken")

        return true
    }

    private func logIn(name: String, server: URL, apiKey: String) async -> Bool {
        let response = await KavitaSourceRunner.getLoginResponse(server: server, apiKey: apiKey)

        guard
            let response,
            let token = response.token,
            let refreshToken = response.refreshToken,
            let apiKey = response.getApiKey()
        else {
            return false
        }

        let key = await SourceManager.shared.createCustomSource(
            kind: .kavita,
            name: name,
            server: server
        )

        UserDefaults.standard.setValue(apiKey, forKey: "\(key).login_key") // populate api key source setting
        UserDefaults.standard.setValue(apiKey, forKey: "\(key).apiKey")
        UserDefaults.standard.setValue(token, forKey: "\(key).token")
        UserDefaults.standard.setValue(refreshToken, forKey: "\(key).refreshToken")

        return true
    }

    private func logIn(name: String, server: URL, cookies: [HTTPCookie]) async -> Bool {
        let response = await KavitaSourceRunner.getLoginResponse(server: server, cookies: cookies)

        guard let response, let cookie = response.cookie else { return false }

        let key = await SourceManager.shared.createCustomSource(
            kind: .kavita,
            name: name,
            server: server
        )

        UserDefaults.standard.setValue("logged_in", forKey: "\(key).login_oidc")
        UserDefaults.standard.setValue(response.getApiKey(), forKey: "\(key).apiKey")
        UserDefaults.standard.setValue(cookie, forKey: "\(key).cookie")

        return true
    }
}
