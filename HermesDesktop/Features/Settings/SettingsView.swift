// MARK: - SettingsView
//
// macOS Settings screen — connection, git sync, and about.

import SwiftUI

// MARK: - SettingsView

/// The macOS Settings screen for Hermes Desktop.
///
/// Organised into three sections:
/// - **Connection**: API URL and API key fields.
/// - **Sync**: git pull status and trigger button.
/// - **About**: app version and GitHub link.
struct SettingsView: View {

    // MARK: State

    @State private var viewModel: SettingsViewModel

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
            connectionSection
            syncSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 400)
        .background(Color.hkPaper)
        .task { await viewModel.load() }
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
                                ? Color.hkAccent
                                : Color.red
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
                .foregroundStyle(Color.hkAccent)
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
