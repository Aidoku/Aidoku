//
//  SettingView+Environment.swift
//  Aidoku
//
//  Created by Skitty on 9/20/25.
//

import AidokuRunner
import SwiftUI

struct SettingPageContentKey: EnvironmentKey {
    static let defaultValue: ((String) -> AnyView?)? = nil
}

struct SettingCustomContentKey: EnvironmentKey {
    static let defaultValue: ((Setting) -> AnyView)? = nil
}

extension EnvironmentValues {
    var settingPageContent: ((String) -> AnyView?)? {
        get { self[SettingPageContentKey.self] }
        set { self[SettingPageContentKey.self] = newValue }
    }

    var settingCustomContent: ((Setting) -> AnyView)? {
        get { self[SettingCustomContentKey.self] }
        set { self[SettingCustomContentKey.self] = newValue }
    }
}

extension View {
    func settingPageContent<Content: View>(
        @ViewBuilder _ content: @escaping (String) -> Content?
    ) -> some View {
        environment(\.settingPageContent) { key in
            if let view = content(key) {
                return AnyView(view)
            } else {
                return nil
            }
        }
    }

    func settingCustomContent<Content: View>(
        @ViewBuilder _ content: @escaping (Setting) -> Content
    ) -> some View {
        environment(\.settingCustomContent) { setting in
            AnyView(content(setting))
        }
    }
}
