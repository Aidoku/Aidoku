//
//  SettingView.swift
//  Aidoku
//
//  Created by Skitty on 3/25/24.
//

import AidokuRunner
import AuthenticationServices
import CommonCrypto
import SafariServices
import SwiftUI

/// View for a given AidokuRunner Setting.
struct SettingView: View {
    let source: AidokuRunner.Source?
    let setting: Setting
    var namespace: String?

    @Binding var hidden: Bool

    @Binding private var stringListBinding: [String]
    @Binding private var doubleBinding: Double

    @State private var requires: Bool
    @State private var requiresFalse: Bool

    @State private var showAddAlert = false
    @State private var showLoginAlert = false
    @State private var showLogoutAlert = false
    @State private var showLoginFailAlert = false
    @State private var showLoginWebConfirm = false
    @State private var showLoginWebView = false
    @State private var showButtonConfirm = false
    @State private var showSafari = false
    @State private var loginCookies: [String: String] = [:]
    @State private var username = ""
    @State private var password = ""
    @State private var listAddItem = ""
    @State private var skippedFirst = false
    @State private var loginLoading = false
    @State private var loginReload = false
    @State private var session: ASWebAuthenticationSession?

    @StateObject private var userDefaultsObserver: UserDefaultsObserver // causes view to refresh when setting changes (e.g. when resetting)
    @StateObject private var requiresObserver: UserDefaultsObserver

    // empty view controller to support login view presentation
    private static var loginShimController = LoginShimViewController()

    init(source: AidokuRunner.Source? = nil, setting: Setting, namespace: String? = nil, hidden: Binding<Bool> = .constant(false)) {
        self.source = source

        // localize the setting title
        // used because the language setting comes from the AidokuRunner package, where it can't be localized
        var setting = setting
        setting.title = NSLocalizedString(setting.title)

        self.setting = setting
        self.namespace = namespace
        self._hidden = hidden

        // need to use this before all properties are initialized
        func key(_ key: String) -> String {
            if key.isEmpty {
                key
            } else if let namespace {
                "\(namespace).\(key)"
            } else {
                key
            }
        }

        _userDefaultsObserver = StateObject(wrappedValue: UserDefaultsObserver(key: key(setting.key)))

        var keys: [String] = []
        if let requires = setting.requires {
            let key = key(requires)
            _requires = State(initialValue: SettingsStore.shared.get(key: key))
            keys.append(key)
        } else {
            _requires = State(initialValue: true)
        }
        if let requiresFalse = setting.requiresFalse {
            let key = key(requiresFalse)
            _requiresFalse = State(initialValue: SettingsStore.shared.get(key: key))
            keys.append(key)
        } else {
            _requiresFalse = State(initialValue: false)
        }
        _requiresObserver = StateObject(wrappedValue: UserDefaultsObserver(keys: keys))

        switch setting.value {
            case .select:
                let key = key(setting.key)
                _stringListBinding = Binding(
                    get: { [SettingsStore.shared.get(key: key)] },
                    set: { SettingsStore.shared.set(key: key, value: $0.first!) }
                )
                _doubleBinding = Binding.constant(0)
            case .multiselect:
                _stringListBinding = SettingsStore.shared.binding(key: key(setting.key))
                _doubleBinding = Binding.constant(0)
            case .editableList:
                _stringListBinding = SettingsStore.shared.binding(key: key(setting.key))
                _doubleBinding = Binding.constant(0)
            case .stepper:
                _stringListBinding = Binding.constant([])
                _doubleBinding = SettingsStore.shared.binding(key: key(setting.key))
            default:
                _stringListBinding = Binding.constant([])
                _doubleBinding = Binding.constant(0)
        }
    }

    var body: some View {
        Group {
            switch setting.value {
                case let .group(value):
                    groupView(value: value)
                case let .select(value):
                    selectView(value: value)
                case let .multiselect(value):
                    multiSelectView(value: value)
                case let .toggle(value):
                    toggleView(value: value)
                case let .stepper(value):
                    stepperView(value: value)
                case let .segment(value):
                    segmentView(value: value)
                case let .text(value):
                    textView(value: value)
                case let .button(value):
                    buttonView(value: value)
                case let .link(value):
                    linkView(value: value)
                case let .login(value):
                    loginView(value: value)
                case let .page(value):
                    pageView(value: value)
                case let .editableList(value):
                    editableListView(value: value)
            }
        }
        .id(key(setting.key))
        .onReceive(userDefaultsObserver.$observedValues) { _ in
            // skip the initial value load
            if !skippedFirst {
                skippedFirst = true
                return
            }
            handleValueChange()
        }
        .onReceive(requiresObserver.$observedValues) { _ in
            if let requires = setting.requires {
                let value = UserDefaults.standard.string(forKey: key(requires))
                self.requires = value != nil && value != "0"
            }
            if let requiresFalse = setting.requiresFalse {
                let value = UserDefaults.standard.string(forKey: key(requiresFalse))
                self.requiresFalse = value != nil && value != "0"
            }
        }
    }

    /// Returns a settings key with the valid namespace
    private func key(_ key: String) -> String {
        if let namespace {
            "\(namespace).\(key)"
        } else {
            key
        }
    }

    private func handleValueChange() {
        func refresh() {
            for refresh in setting.refreshes {
                NotificationCenter.default.post(name: Notification.Name("refresh-\(refresh)"), object: nil)
            }
        }
        if let source, let notification = setting.notification {
            Task {
                do {
                    try await source.handleNotification(notification: notification)
                } catch {
                    LogManager.logger.error("Error handling setting notification for \(source.key): \(error)")
                }
                refresh()
            }
        } else {
            refresh()
        }
        let notificationName = setting.notification ?? key(setting.key)
        NotificationCenter.default.post(name: .init(notificationName), object: nil)
    }
}

// MARK: Group View
extension SettingView {
    @ViewBuilder
    func groupView(value: GroupSetting) -> some View {
        let body = ForEach(value.items.indices, id: \.self) { offset in
            let setting = value.items[offset]
            SettingView(source: source, setting: setting, namespace: namespace)
        }
        if let footer = value.footer.flatMap({ NSLocalizedString($0) }) {
            if !setting.title.isEmpty {
                Section {
                    body
                } header: {
                    Text(setting.title)
                } footer: {
                    Text(footer)
                }
            } else {
                Section {
                    body
                } footer: {
                    Text(footer)
                }
            }
        } else if !setting.title.isEmpty {
            Section(setting.title) {
                body
            }
        } else {
            Section {
                body
            }
        }
    }
}

// MARK: Select View
extension SettingView {
    @ViewBuilder
    func selectView(value: SelectSetting) -> some View {
        NavigationLink {
            List {
                ForEach(value.values.indices, id: \.self) { offset in
                    let item = value.values[offset]
                    let selected = stringListBinding.contains(item)
                    Button {
                        stringListBinding = [item]
                    } label: {
                        HStack {
                            Text(value.titles?[safe: offset] ?? item)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                     .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .onChange(of: stringListBinding) { _ in
                if let item = stringListBinding.first {
                    SettingsStore.shared.set(key: key(setting.key), value: item)
                }
            }
            .navigationTitle(setting.title)
        } label: {
            HStack {
                Text(setting.title)
                Spacer()
                if let item = stringListBinding.first {
                    let title = value.values
                        .firstIndex { $0 == item }
                        .flatMap { value.titles?[safe: $0] }
                    Text(title ?? item)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    func multiSelectView(value: MultiSelectSetting) -> some View {
        NavigationLink(setting.title) {
            List {
                ForEach(value.values.indices, id: \.self) { offset in
                    let item = value.values[offset]
                    let selected = stringListBinding.contains(item)
                    Button {
                        if !selected {
                            stringListBinding.append(item)
                        } else {
                            stringListBinding.removeAll { $0 == item }
                        }
                    } label: {
                        HStack {
                            Text(value.titles?[safe: offset] ?? item)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                     .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .onChange(of: stringListBinding) { _ in
                SettingsStore.shared.set(key: key(setting.key), value: stringListBinding)
            }
            .navigationTitle(setting.title)
        }
    }
}

// MARK: Toggle View
extension SettingView {
    @ViewBuilder
    func toggleView(value: ToggleSetting) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(setting.title)
                    .lineLimit(1)
                if let subtitle = value.subtitle {
                    Text(NSLocalizedString(subtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle(isOn: SettingsStore.shared.binding(key: key(setting.key))) {
                EmptyView()
            }
            .labelsHidden()
        }
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Stepper View
extension SettingView {
    @ViewBuilder
    func stepperView(value: StepperSetting) -> some View {
        HStack {
            Text(setting.title)
                .lineLimit(1)
            Spacer()
            if value.maximumValue >= value.minimumValue {
                Text(String(format: "%g", doubleBinding))
                    .foregroundStyle(.secondary)
                Stepper(
                    "",
                    value: $doubleBinding,
                    in: value.minimumValue...value.maximumValue,
                    step: value.stepValue ?? 1
                )
                .labelsHidden()
            } else {
                Text("Error: Invalid stepper range")
            }
        }
        .disabled(!requires || requiresFalse)
        .transition(.opacity)
    }
}

// MARK: Segment View
extension SettingView {
    @ViewBuilder
    func segmentView(value: SegmentSetting) -> some View {
        HStack {
            Text(setting.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Picker("", selection: SettingsStore.shared.binding(key: key(setting.key)) as Binding<Int>) {
                ForEach(value.options.indices, id: \.self) { offset in
                    Text(value.options[offset])
                        .tag(offset)
                }
            }
            .pickerStyle(.segmented)
        }
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Text View
extension SettingView {
    @ViewBuilder
    func textView(value: TextSetting) -> some View {
        let autocapitalizationType: TextInputAutocapitalization? = value.autocapitalizationType.flatMap {
            switch UITextAutocapitalizationType(rawValue: $0) ?? .sentences {
                case .none: .never
                case .words: .words
                case .sentences: .sentences
                case .allCharacters: .characters
                @unknown default: .sentences
            }
        }
        let returnKeyType: SubmitLabel = value.returnKeyType.flatMap {
            switch UIReturnKeyType(rawValue: $0) ?? .default {
                case .default: .return
                case .go: .go
                case .join: .join
                case .next: .next
                case .route: .route
                case .search: .search
                case .send: .send
                case .done: .done
                case .continue: .continue

                case .google: .return
                case .yahoo: .return
                case .emergencyCall: .return
                @unknown default: .return
            }
        } ?? .return

        Group {
            if value.secure ?? false {
                SecureField(value.placeholder ?? "", text: SettingsStore.shared.binding(key: key(setting.key)))
            } else {
                TextField(value.placeholder ?? "", text: SettingsStore.shared.binding(key: key(setting.key)))
            }
        }
        .textInputAutocapitalization(autocapitalizationType)
        .autocorrectionDisabled(value.autocorrectionDisabled ?? false)
        .keyboardType(value.keyboardType.flatMap { UIKeyboardType(rawValue: $0) } ?? .default)
        .submitLabel(returnKeyType)
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Button View
extension SettingView {
    @ViewBuilder
    func buttonView(value: ButtonSetting) -> some View {
        Button(setting.title, role: (value.destructive ?? false) ? .destructive : nil) {
            if value.confirmTitle != nil || value.confirmText != nil {
                showButtonConfirm = true
            } else {
                handleValueChange()
            }
        }
        .confirmationDialog(
            value.confirmTitle ?? "",
            isPresented: $showButtonConfirm,
            titleVisibility: value.confirmTitle != nil ? .visible : .hidden
        ) {
            Button(NSLocalizedString("OK")) {
                handleValueChange()
            }
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
        } message: {
            if let text = value.confirmText {
                Text(text)
            }
        }
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Link View
extension SettingView {
    @ViewBuilder
    func linkView(value: LinkSetting) -> some View {
        Button(setting.title) {
            showSafari = true
        }
        .fullScreenCover(isPresented: $showSafari) {
            SafariView(url: Binding.constant(URL(string: value.url)))
                .ignoresSafeArea()
        }
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Login View
extension SettingView {
    static let usernameKeySuffix = ".username"
    static let passwordKeySuffix = ".password"
    static let cookieKeysKeySuffix = ".keys"
    static let cookieValuesKeySuffix = ".values"

    @ViewBuilder
    func loginView(value: LoginSetting) -> some View {
        let key = key(setting.key)
        let loggedIn = !(SettingsStore.shared.get(key: key) as String).isEmpty
        Button {
            guard !loggedIn else {
                showLogoutAlert = true
                return
            }
            switch value.method {
                case .basic:
                    if #available(iOS 16.0, *) {
                        showLoginAlert = true
                    } else {
                        showLoginAlertView(value: value)
                    }
                case .oauth:
                    handleOAuthLogin(value: value)
                case .web:
                    showLoginWebConfirm = true
            }
        } label: {
            if loginLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
            } else {
                Text(loggedIn ? value.logoutTitle ?? NSLocalizedString("LOGOUT") : setting.title)
            }
        }
        .disabled(!requires || requiresFalse)
        .alert(setting.title, isPresented: $showLoginAlert) {
            // todo: if useEmail is true, we could verify that the email entered is valid before enabling the log in button
            let useEmail = value.useEmail ?? false
            TextField(useEmail ? NSLocalizedString("EMAIL") : NSLocalizedString("USERNAME"), text: $username)
                .textInputAutocapitalization(.never)
                .textContentType(useEmail ? .emailAddress : .username)
                .keyboardType(useEmail ? .emailAddress : .default)
                .autocorrectionDisabled()
                .submitLabel(.next)
            SecureField(NSLocalizedString("PASSWORD"), text: $password)
                .textContentType(.password)
                .submitLabel(.done)

            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                username = SettingsStore.shared.get(key: key + Self.usernameKeySuffix)
                password = SettingsStore.shared.get(key: key + Self.passwordKeySuffix)
            }
            let is16 = UIDevice.current.systemVersion.hasPrefix("16.")
            Button(NSLocalizedString("LOGIN")) {
                handleBasicLogin(username: username, password: password)
            }
            // the disabled modifier just hides the button on iOS 15/16, so don't use it if we're on those versions
            .disabled(!is16 && (username.isEmpty || password.isEmpty))
        } message: {
            Text(NSLocalizedString("LOGIN_BASIC_TEXT"))
        }
        .alert(NSLocalizedString("LOGIN_WEBVIEW_WARNING"), isPresented: $showLoginWebConfirm) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("LOGIN")) {
                showLoginWebView = true
            }
        } message: {
            Text(NSLocalizedString("LOGIN_WEBVIEW_WARNING_TEXT"))
        }
        .alert(NSLocalizedString("LOGOUT"), isPresented: $showLogoutAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("OK")) {
                SettingsStore.shared.remove(key: key + Self.usernameKeySuffix)
                SettingsStore.shared.remove(key: key + Self.passwordKeySuffix)
                SettingsStore.shared.remove(key: key + Self.cookieKeysKeySuffix)
                SettingsStore.shared.remove(key: key + Self.cookieValuesKeySuffix)
                SettingsStore.shared.remove(key: key)
                username = ""
                password = ""
            }
        } message: {
            Text(NSLocalizedString("LOGOUT_CONFIRM"))
        }
        .alert(NSLocalizedString("LOGIN_FAILED"), isPresented: $showLoginFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            // todo: we can show message from source if they return an error message
            Text(NSLocalizedString("LOGIN_FAILED_TEXT"))
        }
        .fullScreenCover(isPresented: $showLoginWebView) {
            loginWebSheetView(value: value)
        }
        .onAppear {
            username = SettingsStore.shared.get(key: key + Self.usernameKeySuffix)
            password = SettingsStore.shared.get(key: key + Self.passwordKeySuffix)
        }
    }

    // use uikit alert for ios 15, since it doesn't support text fields in alerts
    private func showLoginAlertView(value: LoginSetting) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        var usernameTextField: UITextField?
        var passwordTextField: UITextField?
        delegate.presentAlert(
            title: setting.title,
            message: NSLocalizedString("LOGIN_BASIC_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("LOGIN"), style: .default) { _ in
                    guard
                        let username = usernameTextField?.text,
                        let password = passwordTextField?.text
                    else { return }
                    handleBasicLogin(username: username, password: password)
                }
            ],
            textFieldHandlers: [
                { textField in
                    let useEmail = value.useEmail ?? false
                    textField.placeholder = useEmail ? NSLocalizedString("EMAIL") : NSLocalizedString("USERNAME")
                    textField.textContentType = useEmail ? .emailAddress : .username
                    textField.keyboardType = useEmail ? .emailAddress : .default
                    textField.autocorrectionType = .no
                    textField.autocapitalizationType = .none
                    textField.returnKeyType = .next
                    usernameTextField = textField
                },
                { textField in
                    textField.isSecureTextEntry = true
                    textField.placeholder = NSLocalizedString("PASSWORD")
                    textField.textContentType = .password
                    textField.returnKeyType = .done
                    passwordTextField = textField
                }
            ]
        )
    }

    private func handleBasicLogin(username: String, password: String) {
        guard !(username.isEmpty || password.isEmpty) else {
            return
        }
        let key = key(setting.key)
        @MainActor
        func commit() {
            SettingsStore.shared.set(key: key + Self.usernameKeySuffix, value: username)
            SettingsStore.shared.set(key: key + Self.passwordKeySuffix, value: password)
            SettingsStore.shared.set(key: key, value: "logged_in") // set key to indicate logged in
        }
        if let source, source.features.handlesBasicLogin {
            loginLoading = true
            Task {
                do {
                    let success = try await source.handleBasicLogin(key: setting.key, username: username, password: password)
                    if success {
                        commit()
                    } else {
                        showLoginFailAlert = true
                    }
                } catch {
                    LogManager.logger.error("Error handling basic login for \(source.key): \(error)")
                    showLoginFailAlert = true
                }
                loginLoading = false

                self.username = SettingsStore.shared.get(key: key + Self.usernameKeySuffix)
                self.password = SettingsStore.shared.get(key: key + Self.passwordKeySuffix)
            }
        } else {
            commit()
        }
    }

    private func loginWebSheetView(value: LoginSetting) -> some View {
        PlatformNavigationStack {
            Group {
                if let url = value.url.flatMap({ URL(string: $0) }) {
                    WebView(url, cookies: $loginCookies, reloadToggle: $loginReload)
                        .edgesIgnoringSafeArea(.bottom)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLoginWebView = false
                    } label: {
                        Text(NSLocalizedString("CANCEL")).bold()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loginReload = true
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle(setting.title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: loginCookies) { newValue in
                let key = key(setting.key)
                let keys = Array(newValue.keys)
                let values = keys.map { newValue[$0]! }
                SettingsStore.shared.set(key: key + Self.cookieKeysKeySuffix, value: keys)
                SettingsStore.shared.set(key: key + Self.cookieValuesKeySuffix, value: values)

                func commit() {
                    if newValue.isEmpty {
                        SettingsStore.shared.remove(key: key)
                    } else {
                        SettingsStore.shared.set(key: key, value: "logged_in") // set key to indicate logged in
                    }
                }

                if let source, source.features.handlesWebLogin {
                    Task {
                        do {
                            let success = try await source.handleWebLogin(key: setting.key, cookies: newValue)
                            if success {
                                showLoginWebView = false
                                commit()
                            }
                        } catch {
                            LogManager.logger.error("Error handling web login for \(source.key): \(error)")
                        }
                    }
                } else {
                    commit()
                }
            }
        }
    }

    private func generateCodeVerifier() -> String {
        let length = 128
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        var codeVerifier = ""
        for _ in 0..<length {
            codeVerifier.append(characters.randomElement()!)
        }
        return codeVerifier
    }

    private func generateCodeChallenge(from codeVerifier: String) -> String {
        guard let data = codeVerifier.data(using: .ascii) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        let hashData = Data(hash)
        return hashData.base64EncodedString(options: .endLineWithLineFeed)
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func handleOAuthLogin(value: LoginSetting) {
        let url: URL?

        if let urlString = value.url {
            url = URL(string: urlString)
        } else if let urlKey = value.urlKey {
            url = URL(string: SettingsStore.shared.get(key: key(urlKey)))
        } else {
            url = nil
        }

        guard var url else {
            LogManager.logger.error("Invalid login URL: \(value.url ?? "missing")")
            return
        }

        let key = key(setting.key)

        var codeVerifier: String?
        var clientId: String?
        var redirectUri: String?

        if value.pkce ?? false {
            guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                LogManager.logger.error("Malformed URL: \(url)")
                return
            }
            codeVerifier = generateCodeVerifier()
            SettingsStore.shared.set(key: key + ".codeVerifier", value: codeVerifier!)
            let codeChallenge = generateCodeChallenge(from: codeVerifier!)
            var queryItems = urlComponents.queryItems ?? []
            clientId = queryItems.first(where: { $0.name == "client_id" })?.value
            redirectUri = queryItems.first(where: { $0.name == "redirect_uri" })?.value
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
            queryItems.append(URLQueryItem(name: "response_type", value: "code"))
            urlComponents.queryItems = queryItems

            guard let pkceUrl = urlComponents.url else {
                LogManager.logger.error("Unable to create PKCE URL: \(urlComponents)")
                return
            }
            url = pkceUrl
        }

        session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: value.callbackScheme ?? "aidoku"
        ) { callback, error in
            guard let callback else {
                LogManager.logger.error("No callback URL received")
                return
            }

            loginLoading = true

            defer {
                loginLoading = false
            }

            if value.pkce ?? false, let tokenUrlString = value.tokenUrl {
                guard
                    let codeVerifier,
                    let urlComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                    let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    LogManager.logger.error("Missing code verifier or code")
                    return
                }

                guard let tokenUrl = URL(string: tokenUrlString) else {
                    LogManager.logger.error("Invalid token URL: \(tokenUrlString)")
                    return
                }

                var request = URLRequest(url: tokenUrl)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                var parameters: [String: String] = [
                    "grant_type": "authorization_code",
                    "code": code,
                    "code_verifier": codeVerifier
                ]
                if let redirectUri {
                    parameters["redirect_uri"] = redirectUri
                }
                if let clientId {
                    parameters["client_id"] = clientId
                }

                let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
                request.httpBody = bodyString.data(using: .utf8)

                let task = URLSession.shared.dataTask(with: request) { data, _, error in
                    if let error {
                        LogManager.logger.error("Error requesting access token: \(error.localizedDescription)")
                        return
                    }

                    guard let data else {
                        LogManager.logger.error("No data received from access token request")
                        return
                    }

                    let result = String(decoding: data, as: Unicode.UTF8.self)

                    Task { @MainActor in
                        SettingsStore.shared.set(key: key, value: result)
                    }
                }

                task.resume()
            } else {
                if let error {
                    LogManager.logger.error("Error during login: \(error.localizedDescription)")
                }
                SettingsStore.shared.set(key: key, value: callback.absoluteString)

                if let notification = setting.notification {
                    if let source {
                        Task {
                            do {
                                try await source.handleNotification(notification: notification)
                            } catch {
                                LogManager.logger.error("Error handling setting notification for \(source.key): \(error)")
                            }
                        }
                    }
                    NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
                }
            }
        }

        guard let session else { return }

        session.presentationContextProvider = Self.loginShimController
        session.start()
    }
}

// MARK: Page View
extension SettingView {
    @ViewBuilder
    func pageView(value: PageSetting) -> some View {
        NavigationLink(setting.title) {
            List {
                ForEach(value.items.indices, id: \.self) { offset in
                    let setting = value.items[offset]
                    SettingView(source: source, setting: setting, namespace: namespace)
                }
            }
            .navigationTitle(setting.title)
            .navigationBarTitleDisplayMode((value.inlineTitle ?? false) ? .inline : .automatic)
        }
        .disabled(!requires || requiresFalse)
    }
}

// MARK: Editable List View
extension SettingView {
    @ViewBuilder
    func editableListView(value: EditableListSetting) -> some View {
        let items = ForEach(stringListBinding, id: \.self) { item in
            Text(item)
                .lineLimit(value.lineLimit ?? 0)
        }
        .onDelete { indexSet in
            let newValues: [String] = stringListBinding.enumerated().compactMap { offset, item in
                if indexSet.contains(offset) {
                    nil
                } else {
                    item
                }
            }
            stringListBinding = newValues
        }
        .alert(setting.title, isPresented: $showAddAlert) {
            TextField(value.placeholder ?? "", text: $listAddItem)
            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                listAddItem = ""
            }
            Button(NSLocalizedString("ADD")) {
                stringListBinding.append(listAddItem)
                listAddItem = ""
            }
            .disabled(listAddItem.isEmpty)
        }
        if value.inline ?? false {
            items
            Button {
                showAddAlert = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(NSLocalizedString("ADD"))
                }
            }
            .disabled(!requires || requiresFalse)
        } else {
            NavigationLink {
                List {
                    items
                }
                .navigationTitle(setting.title)
                .toolbar {
#if !os(macOS)
                    let placement = ToolbarItemPlacement.topBarTrailing
#else
                    let placement = ToolbarItemPlacement.primaryAction
#endif
                    ToolbarItem(placement: placement) {
                        Button {
                            showAddAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            } label: {
                Text(setting.title)
            }
            .disabled(!requires || requiresFalse)
        }
    }
}

// MARK: Login Shim View Controller
#if os(macOS)
private class LoginShimViewController: NSViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
#else
private class LoginShimViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
#endif

#Preview {
    let settings: [Setting] = [
        .init(
            title: "Group",
            value: .group(.init(
                footer: "This is a footer.",
                items: [
                    .init(
                        key: "select",
                        title: "Select",
                        value: .select(.init(
                            values: ["1", "2", "3"],
                            titles: ["One", "Two", "Three"]
                        ))
                    ),
                    .init(
                        key: "multi-select",
                        title: "Multi-Select",
                        value: .multiselect(.init(
                            values: ["4", "5", "6"],
                            titles: ["Four", "Five", "Six"]
                        ))
                    ),
                    .init(
                        key: "switch",
                        title: "Switch",
                        value: .toggle(.init(
                            subtitle: "Switch Subtitle"
                        ))
                    )
                ]
            ))
        )
    ]
    return PlatformNavigationStack {
        List {
            ForEach(Array(settings.enumerated()), id: \.offset) { _, setting in
                SettingView(source: nil, setting: setting)
            }
        }
        .navigationTitle("Settings")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
