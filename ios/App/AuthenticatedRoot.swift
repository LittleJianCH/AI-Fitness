import FitnessCore
import SwiftUI

@MainActor struct AuthenticatedRoot: View {
    let endpoint: ServerEndpoint
    let changeServer: () -> Void
    @State private var session: SessionStore
    @State private var settings: SettingsStore
    @State private var username = ""
    @State private var password = ""
    @State private var action: Task<Void, Never>?
    @State private var selectedTab = "workouts"

    init(endpoint: ServerEndpoint, changeServer: @escaping () -> Void) {
        self.endpoint = endpoint
        self.changeServer = changeServer
        let api = FitnessAPI(endpoint: endpoint)
        let session = SessionStore(service: api, vault: KeychainVault(endpoint: endpoint))
        _session = State(initialValue: session)
        _settings = State(initialValue: SettingsStore(service: api, session: session))
    }

    var body: some View {
        Group {
            if case .signedIn = session.phase {
                TabView(selection: $selectedTab) {
                    WorkoutListScreen(api: FitnessAPI(endpoint: endpoint), session: session)
                        .tabItem { Label("Workouts", systemImage: "figure.run") }
                        .tag("workouts")
                    HealthImportScreen(api: FitnessAPI(endpoint: endpoint), session: session)
                        .tabItem { Label("Health", systemImage: "heart") }
                        .tag("health")
                    SettingsScreen(store: settings, server: endpoint.url.absoluteString) { authenticationContent }
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag("account")
                }
                .id(session.generation)
                .tint(.blue)
                .preferredColorScheme(colorScheme)
                .task(id: session.generation) { await settings.load() }
            } else {
                authenticationForm
            }
        }
        .task { await session.restore() }
        .onDisappear { action?.cancel() }
    }

    private var authenticationForm: some View {
        NavigationStack { authenticationContent }
    }

    private var colorScheme: ColorScheme? {
        switch settings.settings?.settingsSoftware.softwareAppearance {
        case .lightAppearance: .light
        case .darkAppearance: .dark
        default: nil
        }
    }

    private var authenticationContent: some View {
        Form {
                switch session.phase {
                case .signedOut, .signingIn:
                    Section {
                        FitnessIntro(title: "Welcome back", subtitle: "Sign in to view your workout and health records.", symbol: "figure.run")
                    }.listRowBackground(Color.clear)
                    Section("Account sign-in") {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("username")
                        SecureField("Password", text: $password)
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
                            Text("Sign in").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 16))
                        .disabled(username.isEmpty || password.isEmpty || session.phase == .signingIn)
                        .accessibilityIdentifier("login")
                        if session.phase == .signingIn { ProgressView("Signing in…") }
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    Button("Change server", action: changeServer).disabled(session.phase == .signingIn)
                case .restoring:
                    ProgressView("Restoring sign-in…")
                case .restoreFailed:
                    Button("Retry restoring sign-in") { action = Task { await session.restore() } }
                    Button("Clear saved credentials", role: .destructive) { session.forgetSavedSession() }
                    Text("Clearing local credentials does not revoke the session on the server.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Change server", action: changeServer)
                case .signedIn(let user), .signingOut(let user):
                    Section {
                        FitnessIntro(title: "\(user.username)", subtitle: "Manage your session on the current server.", symbol: "person.crop.circle.fill")
                    }.listRowBackground(Color.clear)
                    Section("Current account") {
                        LabeledContent(String(localized: "Username"), value: user.username)
                            .accessibilityIdentifier("currentUsername")
                        Button("Sign out", role: .destructive) {
                            action = Task { await session.logout() }
                        }
                        .disabled(session.phase == .signingOut(user))
                        .accessibilityIdentifier("logout")
                    }
                    if session.phase == .signingOut(user) { ProgressView("Signing out…") }
                }
                if let message = session.message {
                    IssueText(message).foregroundStyle(.red).accessibilityIdentifier("sessionError")
                }
            }
            .scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle(session.user == nil ? "AI Fitness" : String(localized: "Account"))
    }
}
