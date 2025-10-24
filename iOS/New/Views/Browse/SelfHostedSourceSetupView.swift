//
//  SelfHostedSourceSetupView.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import SwiftUI

private struct ServerCheck: Hashable {
    let canLoginBasic: Bool
    var canLoginOIDC: Bool = false
    var oidcLoginURL: URL?
}

struct SelfHostedSourceSetupView: View {
    let icon: Image
    let title: String
    let sourceName: String
    let info: String
    let learnMoreUrl: URL?
    let useEmail: Bool

    let demoServer: String
    let demoTitle: String
    let demoInfo: String

    private let checkHandler: (String) async -> ServerCheck
    private let logInHandler: (String, String, String, String) async -> Bool
    private let oidcLogInHandler: ((String, String, [HTTPCookie]) async -> Bool)?

    @State private var name: String
    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""

    private enum ViewState: Equatable {
        case initial
        case loading
        case logIn(ServerCheck)
        case loadingLogin(ServerCheck)
    }

    private enum ServerError {
        case connection
        case authorization
    }

    @State private var state: ViewState = .initial
    @State private var error: ServerError?
    @State private var showLoginSheet = false

    private var isLogInState: Bool {
        if case .logIn = state { return true }
        return false
    }
    private var isLoadingLoginState: Bool {
        if case .loadingLogin = state { return true }
        return false
    }
    private var loginCheck: ServerCheck? {
        if case let .logIn(check) = state {
            return check
        } else if case let .loadingLogin(check) = state {
            return check
        }
        return nil
    }

    @State private var uniqueName = true
    @State private var uniqueServer = true

    enum Field: Int, Hashable {
        case name
        case server
        case username
        case password
    }

    @FocusState private var focusedField: Field?

    private var existingServers: Set<String>

    @EnvironmentObject private var path: NavigationCoordinator

    fileprivate init(
        icon: Image,
        title: String,
        sourceName: String,
        info: String,
        learnMoreUrl: URL?,
        sourceKeyPrefix: String,
        useEmail: Bool,
        demoServer: String,
        demoTitle: String,
        demoInfo: String,
        checkServer: @escaping (String) async -> ServerCheck,
        logIn: @escaping (String, String, String, String) async -> Bool,
        oidcLogIn: ((String, String, [HTTPCookie]) async -> Bool)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.sourceName = sourceName
        self.info = info
        self.learnMoreUrl = learnMoreUrl
        self.useEmail = useEmail
        self.demoServer = demoServer
        self.demoTitle = demoTitle
        self.demoInfo = demoInfo
        self.checkHandler = checkServer
        self.logInHandler = logIn
        self.oidcLogInHandler = oidcLogIn

        // find unique default name
        var defaultName = sourceName
        var counter = 2
        while SourceManager.shared.sources.contains(where: { $0.name == defaultName }) {
            defaultName = "\(sourceName) \(counter)"
            counter += 1
        }
        self._name = State(initialValue: defaultName)

        // store existing komga servers to check against for uniqueness
        let relatedSources = SourceManager.shared.sources.filter({ $0.id.hasPrefix(sourceKeyPrefix) })
        self.existingServers = Set(relatedSources.compactMap { UserDefaults.standard.string(forKey: "\($0.key).server") })
    }

    var body: some View {
        let isLoading = state == .loading || isLoadingLoginState
        let submitDisabled = submitDisabled
        List {
            Section {
                SettingHeaderView(
                    icon: .raw(icon),
                    title: sourceName,
                    subtitle: info,
                    learnMoreUrl: learnMoreUrl
                )
            }

            Section {
                TextField(sourceName, text: $name)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { self.focusNextField($focusedField) }
                    .disabled(isLoading)
            } header: {
                Text(NSLocalizedString("SOURCE_NAME"))
            } footer: {
                if !uniqueName {
                    Text(NSLocalizedString("SOURCE_NAME_UNIQUE_ERROR"))
                        .foregroundStyle(.red)
                } else {
                    Text(NSLocalizedString("SOURCE_NAME_INFO"))
                }
            }
            Section {
                TextField(demoServer, text: $server)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .server)
                    .onSubmit {
                        if !submitDisabled {
                            submit()
                        }
                    }
                    .submitLabel(.done)
                    .disabled(isLoading)
                    .onChange(of: server) { _ in
                        if isLogInState {
                            state = .initial
                        }
                    }
            } header: {
                Text(NSLocalizedString("SERVER_URL"))
            } footer: {
                if !uniqueServer {
                    Text(NSLocalizedString("SERVER_URL_UNIQUE_ERROR"))
                        .foregroundStyle(.red)
                } else {
                    Text(NSLocalizedString("SERVER_URL_INFO"))
                }
            }

            if let check = loginCheck {
                if check.canLoginBasic {
                    Section(NSLocalizedString("LOGIN")) {
                        Group {
                            if useEmail {
                                TextField(NSLocalizedString("EMAIL"), text: $username)
                                    .textContentType(.emailAddress)
                            } else {
                                TextField(NSLocalizedString("USERNAME"), text: $username)
                                    .textContentType(.username)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { self.focusNextField($focusedField) }
                        .disabled(isLoading)

                        SecureField(NSLocalizedString("PASSWORD"), text: $password)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .password)
                            .onSubmit {
                                if !submitDisabled {
                                    submit()
                                }
                            }
                            .disabled(isLoading)
                    }
                }
                if check.canLoginOIDC, let loginURL = check.oidcLoginURL {
                    Section {
                        Button(NSLocalizedString("LOGIN_VIA_OIDC")) {
                            showLoginSheet = true
                        }
                        .sheet(isPresented: $showLoginSheet) {
                            OIDCLoginView(loginURL: loginURL) { cookies in
                                Task {
                                    await logIn(cookies: cookies)
                                }
                            }
                            .interactiveDismissDisabled()
                        }
                    }
                }
            }

            if (isLogInState || isLoadingLoginState) && server == demoServer {
                Section {
                    LocalSetupView.infoView(
                        title: LocalizedStringKey(demoTitle),
                        subtitle: LocalizedStringKey(demoInfo)
                    )
                }
            }

            if let error {
                Section {
                    switch error {
                        case .connection:
                            LocalSetupView.infoView(
                                title: LocalizedStringKey(NSLocalizedString("SERVER_ERROR")),
                                subtitle: LocalizedStringKey(NSLocalizedString("SERVER_ERROR_CONNECTION")),
                                error: true
                            )
                        case .authorization:
                            LocalSetupView.infoView(
                                title: LocalizedStringKey(NSLocalizedString("SERVER_ERROR")),
                                subtitle: LocalizedStringKey(NSLocalizedString("SERVER_ERROR_AUTHENTICATION")),
                                error: true
                            )
                    }
                }
            }
        }
        .onChange(of: name) { _ in
            ensureUniqueName()
        }
        .onChange(of: server) { _ in
            ensureUniqueServer()
        }
        .animation(.default, value: state)
        .animation(.default, value: error)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    submit()
                } label: {
                    if #available(iOS 26.0, *) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text(NSLocalizedString("CONTINUE"))
                        }
                    } else {
                        ZStack(alignment: .trailing) {
                            if isLoading {
                                ProgressView().progressViewStyle(.circular)
                            }
                            Text(NSLocalizedString("CONTINUE"))
                                .opacity(isLoading ? 0 : 1) // fixes weird transition animation
                        }
                    }
                }
                .disabled(submitDisabled)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    var submitDisabled: Bool {
        server.isEmpty || name.isEmpty
            || !uniqueName || !uniqueServer
            || state == .loading || isLoadingLoginState
            || (isLogInState && (username.isEmpty || password.isEmpty))
    }

    func submit() {
        switch state {
            case .initial:
                Task {
                    await checkServer()
                }
            case .logIn:
                Task {
                    await logIn()
                }
            default:
                break
        }
    }

    func ensureUniqueName() {
        let name = name.trimmingCharacters(in: .whitespaces)
        uniqueName = !SourceManager.shared.sources.contains(where: { $0.name == name })
    }

    func ensureUniqueServer() {
        let serverString = (server.last == "/" ? String(server[..<server.index(before: server.endIndex)]) : server)
            .trimmingCharacters(in: .whitespaces)
        uniqueServer = !existingServers.contains(serverString)
    }

    func checkServer() async {
        error = nil
        state = .loading

        // trim whitespace
        name = name.trimmingCharacters(in: .whitespaces)
        server = server.trimmingCharacters(in: .whitespaces)

        // remove trailing slash
        if server.last == "/" {
            server.removeLast()
        }

        let serverCheck = await checkHandler(server)
        guard serverCheck.canLoginBasic || serverCheck.canLoginOIDC else {
            state = .initial
            error = .connection
            return
        }

        state = .logIn(serverCheck)
    }

    func logIn(cookies: [HTTPCookie] = []) async {
        guard case let .logIn(check) = state else {
            return
        }
        error = nil
        state = .loadingLogin(check)

        // trim whitespace (again, in case name was changed)
        name = name.trimmingCharacters(in: .whitespaces)

        let didLogIn = if !cookies.isEmpty, let oidcLogInHandler {
            await oidcLogInHandler(name, server, cookies)
        } else {
            await logInHandler(name, server, username, password)
        }

        guard didLogIn else {
            state = .logIn(check)
            error = .authorization
            return
        }

        path.dismiss()
    }
}

struct KomgaSetupView: View {
    var body: some View {
        SelfHostedSourceSetupView(
            icon: Image(.komga),
            title: NSLocalizedString("KOMGA_SETUP"),
            sourceName: NSLocalizedString("KOMGA"),
            info: NSLocalizedString("KOMGA_INFO"),
            learnMoreUrl: URL(string: "https://komga.org/docs/introduction"),
            sourceKeyPrefix: "komga.",
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

    private func logIn(name: String, server: String, username: String, password: String) async -> Bool {
        // request the user info endpoint to ensure we can authenticate
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
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

struct KavitaSetupView: View {
    var body: some View {
        SelfHostedSourceSetupView(
            icon: Image(.kavita),
            title: NSLocalizedString("KAVITA_SETUP"),
            sourceName: NSLocalizedString("KAVITA"),
            info: NSLocalizedString("KAVITA_INFO"),
            learnMoreUrl: URL(string: "https://wiki.kavitareader.com/getting-started/"),
            sourceKeyPrefix: "kavita.",
            useEmail: false,
            demoServer: "https://demo.kavitareader.com",
            demoTitle: NSLocalizedString("DEMO_KAVITA_SERVER"),
            demoInfo: NSLocalizedString("DEMO_KAVITA_SERVER_INFO"),
            checkServer: check(server:),
            logIn: logIn(name:server:username:password:),
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

        let check: Bool? = try? await URLSession.shared.object(from: testUrl)
        guard check == true else {
            return ServerCheck(canLoginBasic: false)
        }

        struct OIDCResponse: Decodable {
            let disablePasswordAuthentication: Bool
            let enabled: Bool
            let providerName: String
        }
        let response: OIDCResponse? = try? await URLSession.shared.object(from: oidcCheckUrl)

        guard let response else {
            return ServerCheck(canLoginBasic: false)
        }

        return ServerCheck(
            canLoginBasic: !response.disablePasswordAuthentication,
            canLoginOIDC: response.enabled,
            oidcLoginURL: URL(string: server + "/oidc/login?returnURL=aidoku://oidc-auth")
        )
    }

    private func logIn(name: String, server: String, username: String, password: String) async -> Bool {
        let response = await Self.getLoginResponse(server: server, username: username, password: password)

        guard
            let response,
            let token = response.token,
            let refreshToken = response.refreshToken,
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

        UserDefaults.standard.setValue(response.apiKey, forKey: "\(key).apiKey")
        UserDefaults.standard.setValue(token, forKey: "\(key).token")
        UserDefaults.standard.setValue(refreshToken, forKey: "\(key).refreshToken")

        return true
    }

    private func logIn(name: String, server: String, cookies: [HTTPCookie]) async -> Bool {
        let response = await Self.getLoginResponse(server: server, cookies: cookies)

        guard let response, let cookie = response.cookie else { return false }

        let key = await SourceManager.shared.createCustomSource(
            kind: .kavita,
            name: name,
            server: server
        )

        UserDefaults.standard.setValue("logged_in", forKey: "\(key).login_oidc")
        UserDefaults.standard.setValue(response.apiKey, forKey: "\(key).apiKey")
        UserDefaults.standard.setValue(cookie, forKey: "\(key).cookie")

        return true
    }

    struct LoginResponse: Decodable {
        let apiKey: String
        let username: String
        let token: String?
        let refreshToken: String?
        var cookie: String?
    }

    static func getLoginResponse(server: String, username: String, password: String) async -> LoginResponse? {
        guard let loginUrl = URL(string: server + "/api/account/login") else {
            return nil
        }

        struct Payload: Encodable {
            let username: String
            let password: String
            let apiKey: String
        }

        let payload = Payload(username: username, password: password, apiKey: "")

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try? await URLSession.shared.object(from: request)
    }

    static func getLoginResponse(server: String, cookies: [HTTPCookie]) async -> LoginResponse? {
        guard
            let cookie = cookies.first(where: { $0.name == ".AspNetCore.Cookies" }),
            let accountUrl = URL(string: server + "/api/account")
        else {
            return nil
        }

        var request = URLRequest(url: accountUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in HTTPCookie.requestHeaderFields(with: [cookie]) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var response: LoginResponse? = try? await URLSession.shared.object(from: request)
        response?.cookie = request.value(forHTTPHeaderField: "Cookie")
        return response
    }
}

#Preview {
    KomgaSetupView()
}
