// MARK: - SettingsView
//
// macOS Settings screen — general, connection, git sync, and about.
// The General section is expected to grow (agent name today; more
// app-level preferences later) — add new fields there.

import SwiftUI

// MARK: - SettingsView

/// The macOS Settings screen for Hermes Desktop.
///
/// Organised into four sections:
/// - **General**: app-level preferences (agent display name, …).
/// - **Connection**: API URL and API key fields.
/// - **Sync**: git pull status and trigger button.
/// - **About**: app version and GitHub link.
struct SettingsView: View {

    // MARK: State

    @State private var viewModel: SettingsViewModel

    /// Agent display name shown in the sidebar footer. No hardcoded
    /// default: empty falls back to "Hermes" in the sidebar.
    @AppStorage("agent_name") private var agentName: String = ""

    // MARK: Initializer

    /// Creates a settings view with the required dependencies.
    ///
    /// - Parameters:
    ///   - keychainManager: For reading / writing the API key.
    ///   - gitSyncService: For triggering git sync.
    init(keychainManager: KeychainManager, gitSyncService: GitSyncService) {
        _viewModel = State(
            initialValue: SettingsViewModel(
                keychainManager: keychainManager,
                gitSyncService: gitSyncService
            )
        )
    }

    // MARK: Body

    var body: some View {
        Form {
            generalSection
            connectionSection
            syncSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
        .background(Color.hkPage)
        .task { await viewModel.load() }
    }

    // MARK: - General Section

    @ViewBuilder
    private var generalSection: some View {
        Section("General") {
            TextField(
                "Agent name",
                text: $agentName,
                prompt: Text("Hermes")
            )
            .font(.hkBody)
            .textFieldStyle(.roundedBorder)

            Text("Shown in the sidebar footer. Saved automatically.")
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
        }
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            TextField(
                "API URL",
                text: $viewModel.apiURL,
                prompt: Text("e.g. http://vps:8642")
            )
            .font(.hkBody)
            .textFieldStyle(.roundedBorder)

            SecureField(
                "API Key",
                text: $viewModel.apiKey,
                prompt: Text("Paste your Hermes API key")
            )
            .font(.hkBody)
            .textFieldStyle(.roundedBorder)

            HStack {
                if let feedback = viewModel.feedbackMessage {
                    Text(feedback)
                        .font(.hkCaption)
                        .foregroundStyle(
                            feedback == "Settings saved"
                                ? Color.hkAccent2
                                : Color.hkError
                        )
                        .onTapGesture { viewModel.clearFeedback() }
                }

                Spacer()

                Button("Save") {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Sync Section

    @ViewBuilder
    private var syncSection: some View {
        Section("Git Sync") {
            HStack {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Pulls latest agents-hub from GitHub.")
                        .font(.hkCaption)
                        .foregroundStyle(Color.hkNeutral)

                    Text(viewModel.syncStatus)
                        .font(.hkCaption)
                        .foregroundStyle(Color.hkMuted)
                }

                Spacer()

                Button("Sync Now") {
                    Task { await viewModel.syncNow() }
                }
                .disabled(viewModel.isSyncing)
            }
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                    .font(.hkBody)
                    .foregroundStyle(Color.hkInk)

                Spacer()

                Text(viewModel.appVersion)
                    .font(.hkBody)
                    .foregroundStyle(Color.hkMuted)
            }

            HStack {
                Text("Hermes Desktop")
                    .font(.hkBody)
                    .foregroundStyle(Color.hkInk)

                Spacer()

                Link("GitHub", destination: URL(
                    string: "https://github.com/nousresearch/hermes-desktop"
                )!)
                .font(.hkBody)
                .foregroundStyle(Color.hkAccent2)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView(
        keychainManager: KeychainManager(),
        gitSyncService: GitSyncService()
    )
}
