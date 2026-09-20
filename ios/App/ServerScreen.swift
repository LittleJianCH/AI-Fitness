import FitnessCore
import SwiftUI

@MainActor struct ServerScreen: View {
    @AppStorage("serverOrigin") private var savedOrigin = ""
    @State private var origin = ""
    @State private var endpoint: ServerEndpoint?
    @State private var error: ClientIssue?

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
                            FitnessIntro(title: "Connect your workout records", subtitle: "Connect to a server to view workouts and exchange data with Apple Health.", symbol: "figure.outdoor.cycle")
                        }.listRowBackground(Color.clear)
                        Section {
                            TextField("https://fitness.example.com", text: $origin)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("serverOrigin")
                        } header: { Text("Server address") }
                        footer: { Text("Credentials are stored separately for each server on this device.") }
                        if let error { IssueText(error).foregroundStyle(.red) }
                        Button(action: connect) { Text("Connect").frame(maxWidth: .infinity).padding(.vertical, 4) }
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
        } catch { self.error = ClientIssue(error) }
    }
}
