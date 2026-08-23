//
//  SettingsAboutView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text(NSLocalizedString("VERSION"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(NSLocalizedString("BUILD"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SettingView(setting: .init(
                    title: NSLocalizedString("GITHUB_REPO"),
                    value: .link(.init(url: "https://github.com/Aidoku/Aidoku"))
                ))
                SettingView(setting: .init(
                    title: NSLocalizedString("DISCORD_SERVER"),
                    value: .link(.init(url: "https://discord.gg/9U8cC5Zk3s", external: true))
                ))
                SettingView(setting: .init(
                    title: NSLocalizedString("SUPPORT_VIA_KOFI"),
                    value: .link(.init(url: "https://ko-fi.com/skittyblock", external: true))
                ))
            }
        }
        .navigationTitle(NSLocalizedString("ABOUT"))
    }
}
