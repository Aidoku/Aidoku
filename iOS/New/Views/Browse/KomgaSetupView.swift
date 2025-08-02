//
//  KomgaSetupView.swift
//  Aidoku
//
//  Created by Skitty on 5/24/25.
//

import SwiftUI

struct KomgaSetupView: View {
    @State private var name: String
    @State private var server: String = ""
    @State private var email: String = ""
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
        case email
        case password
    }

    @FocusState private var focusedField: Field?

    private var existingKomgaServers: Set<String>

    @EnvironmentObject private var path: NavigationCoordinator

    static private let demoKomgaServer = "https://demo.komga.org"

    init() {
        // find unique default name
        var defaultName = NSLocalizedString("KOMGA")
        var counter = 2
        while SourceManager.shared.sources.contains(where: { $0.name == defaultName }) {
            defaultName = "Komga \(counter)"
            counter += 1
        }
        self._name = State(initialValue: defaultName)

        // store existing komga servers to check against for uniqueness
        let komgaSources = SourceManager.shared.sources.filter({ $0.id.hasPrefix("komga.") })
        self.existingKomgaServers = Set(komgaSources.compactMap { UserDefaults.standard.string(forKey: "\($0.key).server") })
    }

    var body: some View {
        let isLoading = state == .loading || state == .loadingLogin
        let submitDisabled = submitDisabled
        List {
            Section {
                LocalSetupView.infoView(
                    title: LocalizedStringKey(NSLocalizedString("KOMGA")),
                    subtitle: LocalizedStringKey(NSLocalizedString("KOMGA_INFO"))
                )
            }

            Section {
                TextField(NSLocalizedString("KOMGA"), text: $name)
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
                TextField(String(Self.demoKomgaServer), text: $server)
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
                    TextField(NSLocalizedString("EMAIL"), text: $email)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
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

            if (state == .logIn || state == .loadingLogin) && server == Self.demoKomgaServer {
                Section {
                    LocalSetupView.infoView(
                        title: LocalizedStringKey(NSLocalizedString("DEMO_KOMGA_SERVER")),
                        subtitle: LocalizedStringKey(NSLocalizedString("DEMO_KOMGA_SERVER_INFO"))
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
                
                    ZStack(alignment: .trailing) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular)
                        }
                        Text(NSLocalizedString("CONTINUE"))
                            .opacity(isLoading ? 0 : 1) // fixes weird transition animation
                    }
                
                }
                .disabled(submitDisabled)
            }
        }
        .navigationTitle(NSLocalizedString("KOMGA_SETUP"))
        .navigationBarTitleDisplayMode(.inline)
    }

    var submitDisabled: Bool {
        server.isEmpty || name.isEmpty
            || !uniqueName || !uniqueServer
            || state == .loading || state == .loadingLogin
            || (state == .logIn && (email.isEmpty || password.isEmpty))
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
        uniqueServer = !existingKomgaServers.contains(serverString)
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

        // ensure url is valid (shouldn't fail)
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
            state = .initial
            error = .connection
            return
        }

        // request the user info endpoint to ensure it gives us an komga auth error
        var request = URLRequest(url: testUrl)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: KomgaError? = try? await URLSession.shared.object(from: testUrl)

        guard let response, response.error == "Unauthorized" else {
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

        // request the user info endpoint to ensure we can authenticate
        guard let testUrl = URL(string: server + "/api/v2/users/me") else {
            state = .initial
            error = .connection
            return
        }

        var request = URLRequest(url: testUrl)
        let auth = Data("\(email):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct Response: Codable {
            let email: String
        }
        let response: Response? = try? await URLSession.shared.object(from: request)

        guard let response, response.email == email else {
            state = .logIn
            error = .authorization
            return
        }

        await SourceManager.shared.createKomgaSource(
            name: name,
            server: server,
            email: email,
            password: password
        )

        path.dismiss()
    }
}

#Preview {
    KomgaSetupView()
}
