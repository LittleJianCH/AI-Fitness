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
                            FitnessIntro(title: "连接你的训练记录", subtitle: "连接服务器后，即可查看运动记录并与 Apple 健康交换数据。", symbol: "figure.outdoor.cycle")
                        }.listRowBackground(Color.clear)
                        Section {
                            TextField("https://fitness.example.com", text: $origin)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("serverOrigin")
                        } header: { Text("服务器地址") }
                        footer: { Text("登录凭据会按服务器地址分别保存在本机。") }
                        if let error { Text(error).foregroundStyle(.red) }
                        Button(action: connect) { Text("连接").frame(maxWidth: .infinity).padding(.vertical, 4) }
                            .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 16))
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .accessibilityIdentifier("connectServer")
                    }
                    .scrollContentBackground(.hidden).background(FitnessStyle.background)
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
    @State private var selectedTab = "workouts"

    init(endpoint: ServerEndpoint, changeServer: @escaping () -> Void) {
        self.endpoint = endpoint
        self.changeServer = changeServer
        _session = State(initialValue: SessionStore(service: FitnessAPI(endpoint: endpoint), vault: KeychainVault(endpoint: endpoint)))
    }

    var body: some View {
        Group {
            if case .signedIn = session.phase {
                TabView(selection: $selectedTab) {
                    WorkoutListScreen(api: FitnessAPI(endpoint: endpoint), session: session)
                        .tabItem { Label("运动", systemImage: "figure.run") }
                        .tag("workouts")
                    HealthImportScreen(api: FitnessAPI(endpoint: endpoint), session: session)
                        .tabItem { Label("健康", systemImage: "heart") }
                        .tag("health")
                    authenticationForm
                        .tabItem { Label("账号", systemImage: "person.crop.circle") }
                        .tag("account")
                }
                .id(session.generation)
                .tint(.blue)
            } else {
                authenticationForm
            }
        }
        .task { await session.restore() }
        .onDisappear { action?.cancel() }
    }

    private var authenticationForm: some View {
        NavigationStack {
            Form {
                switch session.phase {
                case .signedOut, .signingIn:
                    Section {
                        FitnessIntro(title: "欢迎回来", subtitle: "登录后，继续查看你的运动与健康记录。", symbol: "figure.run")
                    }.listRowBackground(Color.clear)
                    Section("账号登录") {
                        TextField("用户名", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("username")
                        SecureField("密码", text: $password)
                            .textContentType(.password)
                            .accessibilityIdentifier("password")
                    }
                    Section {
                        Button {
                            let secret = password
                            let name = username
                            password = ""
                            action = Task { await session.login(username: name, password: secret, deviceName: UIDevice.current.model) }
                        } label: {
                            Text("登录").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 16))
                        .disabled(username.isEmpty || password.isEmpty || session.phase == .signingIn)
                        .accessibilityIdentifier("login")
                        if session.phase == .signingIn { ProgressView("正在登录…") }
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
                    Section {
                        FitnessIntro(title: user.username, subtitle: "管理当前服务器的登录会话。", symbol: "person.crop.circle.fill")
                    }.listRowBackground(Color.clear)
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
            .scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle(session.user == nil ? "AI Fitness" : "账号")
        }
    }
}
