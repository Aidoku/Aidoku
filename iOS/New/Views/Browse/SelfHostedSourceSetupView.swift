//
//  SelfHostedSourceSetupView.swift
//  Aidoku
//
//  Created by Skitty on 10/19/25.
//

import SwiftUI

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

    let checkHandler: (String) async -> Bool
    let logInHandler: (String, String, String, String) async -> Bool

    @State private var name: String
    @State private var server: String = ""
    @State private var username: String = ""
    @State private var password: String = ""

    enum ViewState {
        case initial
        case loading
        case logIn
        case loadingLogin
    }

    enum ServerError {
        case connection
        case authorization
    }

    @State private var state: ViewState = .initial
    @State private var error: ServerError?

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

    init(
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
        checkServer: @escaping (String) async -> Bool,
        logIn: @escaping (String, String, String, String) async -> Bool
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
        let isLoading = state == .loading || state == .loadingLogin
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
                        if state == .logIn {
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

            if state == .logIn || state == .loadingLogin {
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

            if (state == .logIn || state == .loadingLogin) && server == demoServer {
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
            || state == .loading || state == .loadingLogin
            || (state == .logIn && (username.isEmpty || password.isEmpty))
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

        let isValidServer = await checkHandler(server)
        guard isValidServer else {
            state = .initial
            error = .connection
            return
        }

        state = .logIn
    }

    func logIn() async {
        error = nil
        state = .loadingLogin

        // trim whitespace (again, in case name was changed)
        name = name.trimmingCharacters(in: .whitespaces)

        let didLogIn = await logInHandler(name, server, username, password)
        guard didLogIn else {
            state = .logIn
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

    func check(server: String) async -> Bool {
        // ensure url is valid (shouldn't fail)
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
            return false
        }

        // request the user info endpoint to ensure it gives us an komga auth error
        let response: KomgaError? = try? await URLSession.shared.object(from: testUrl)

        guard let response, response.error == "Unauthorized" else {
            return false
        }

        return true
    }

    func logIn(name: String, server: String, username: String, password: String) async -> Bool {
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
            logIn: logIn(name:server:username:password:)
        )
    }

    func check(server: String) async -> Bool {
        // ensure url is valid (shouldn't fail)
        guard let testUrl = URL(string: server + "/api/admin/exists") else {
            return false
        }

        let response: Bool? = try? await URLSession.shared.object(from: testUrl)

        guard response == true else {
            return false
        }

        return true
    }

    func logIn(name: String, server: String, username: String, password: String) async -> Bool {
        guard let loginUrl = URL(string: server + "/api/account/login") else {
            return false
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

        struct Response: Decodable {
            let apiKey: String
            let username: String
            let token: String
            let refreshToken: String
        }
        let response: Response? = try? await URLSession.shared.object(from: request)

        guard let response, response.username == username else {
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
        UserDefaults.standard.setValue(response.token, forKey: "\(key).token")
        UserDefaults.standard.setValue(response.refreshToken, forKey: "\(key).refreshToken")

        return true
    }
}

#Preview {
    KomgaSetupView()
}
