import FitnessCore
import SwiftUI

@main @MainActor
struct FitnessApp: App {
    var body: some Scene {
        WindowGroup { ServerScreen() }
    }
}

@MainActor struct ServerScreen: View {
    @AppStorage("serverOrigin") private var savedOrigin = ""
    @State private var origin = ""
    @State private var endpoint: ServerEndpoint?
    @State private var error: String?

    var body: some View {
        Group {
            if let endpoint {
                AuthenticatedRoot(endpoint: endpoint) {
                    self.endpoint = nil
                }
                .id(endpoint)
            } else {
                NavigationStack {
                    Form {
                        Section {
                            TextField("https://fitness.example.com", text: $origin)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("serverOrigin")
                        } header: { Text("连接你的 AI Fitness") }
                        footer: { Text("请输入后端地址。登录凭据会按地址分别保存在本机。") }
                        if let error { Text(error).foregroundStyle(.red) }
                        Button("连接", action: connect).accessibilityIdentifier("connectServer")
                    }
                    .navigationTitle("AI Fitness")
                }
            }
        }
        .task {
            guard origin.isEmpty, endpoint == nil else { return }
            origin = savedOrigin
            if !origin.isEmpty { connect() }
        }
    }

    private func connect() {
        do {
            #if DEBUG
            let parsed = try ServerEndpoint(origin, allowLoopbackHTTP: true)
            #else
            let parsed = try ServerEndpoint(origin)
            #endif
            savedOrigin = parsed.credentialScope
            endpoint = parsed
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor struct AuthenticatedRoot: View {
    let endpoint: ServerEndpoint
    let changeServer: () -> Void
    @State private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var action: Task<Void, Never>?

    init(endpoint: ServerEndpoint, changeServer: @escaping () -> Void) {
        self.endpoint = endpoint
        self.changeServer = changeServer
        _session = State(initialValue: SessionStore(service: FitnessAPI(endpoint: endpoint), vault: KeychainVault(endpoint: endpoint)))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch session.phase {
                case .signedOut, .signingIn:
                    Section("账号登录") {
                        TextField("用户名", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("username")
                        SecureField("密码", text: $password)
                            .textContentType(.password)
                            .accessibilityIdentifier("password")
                        Button("登录") {
                            let secret = password
                            let name = username
                            password = ""
                            action = Task { await session.login(username: name, password: secret, deviceName: UIDevice.current.model) }
                        }
                        .disabled(username.isEmpty || password.isEmpty || session.phase == .signingIn)
                        .accessibilityIdentifier("login")
                        if session.phase == .signingIn { ProgressView("正在登录…") }
                    }
                    Button("更换服务器", action: changeServer).disabled(session.phase == .signingIn)
                case .restoring:
                    ProgressView("正在恢复登录…")
                case .restoreFailed:
                    Button("重试恢复登录") { action = Task { await session.restore() } }
                    Button("清除本机凭据", role: .destructive) { session.forgetSavedSession() }
                    Text("清除本机凭据不会撤销服务器上的会话。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("更换服务器", action: changeServer)
                case .signedIn(let user), .signingOut(let user):
                    Section("当前账号") {
                        LabeledContent("用户名", value: user.username)
                            .accessibilityIdentifier("currentUsername")
                        Button("退出登录", role: .destructive) {
                            action = Task { await session.logout() }
                        }
                        .disabled(session.phase == .signingOut(user))
                        .accessibilityIdentifier("logout")
                    }
                    if session.phase == .signingOut(user) { ProgressView("正在退出…") }
                }
                if let message = session.message {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("sessionError")
                }
            }
            .navigationTitle("AI Fitness")
        }
        .task { await session.restore() }
        .onDisappear { action?.cancel() }
    }
}
