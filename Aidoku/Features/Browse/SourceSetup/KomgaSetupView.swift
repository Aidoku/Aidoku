//
//  KomgaSetupView.swift
//  Aidoku
//
//  Created by skitty on 7/5/26.
//

import SwiftUI

struct KomgaSetupView: View {
    var body: some View {
        SelfHostedSourceSetupView(
            icon: Image(.komga),
            title: NSLocalizedString("KOMGA_SETUP"),
            sourceName: NSLocalizedString("KOMGA"),
            info: NSLocalizedString("KOMGA_INFO"),
            learnMoreUrl: URL(string: "https://komga.org/docs/introduction"),
            sourceKeyPrefix: KomgaSourceRunner.sourceKeyPrefix,
            useEmail: true,
            demoServer: "https://demo.komga.org",
            demoTitle: NSLocalizedString("DEMO_KOMGA_SERVER"),
            demoInfo: NSLocalizedString("DEMO_KOMGA_SERVER_INFO"),
            checkServer: check(server:),
            logIn: logIn(name:server:username:password:)
        )
    }

    private func check(server: String) async -> ServerCheck {
        // ensure url is valid (shouldn't fail)
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
            return ServerCheck(canLoginBasic: false)
        }

        // request the user info endpoint to ensure it gives us an komga auth error
        let response: KomgaError? = try? await URLSession.shared.object(from: testUrl)

        guard let response, response.error == "Unauthorized" else {
            return ServerCheck(canLoginBasic: false)
        }

        return ServerCheck(canLoginBasic: true)
    }

    private func logIn(name: String, server: URL, username: String, password: String) async -> Bool {
        // request the user info endpoint to ensure we can authenticate
        guard let testUrl = URL(string: "api/v2/users/me", relativeTo: server) else {
            return false
        }

        var request = URLRequest(url: testUrl)
        let auth = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Response: Codable {
            let email: String
        }
        let response: Response? = try? await URLSession.shared.object(from: request)

        guard let response, response.email == username else {
            return false
        }

        await SourceManager.shared.createCustomSource(
            kind: .komga,
            name: name,
            server: server,
            username: username,
            password: password
        )

        return true
    }
}
