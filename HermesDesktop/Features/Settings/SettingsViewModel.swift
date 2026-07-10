// MARK: - SettingsViewModel
//
// View model for the Settings screen — manages API credentials,
// git sync status, and app version display.

import Foundation
import Observation

// MARK: - SettingsViewModel

/// View model for the macOS Settings screen.
///
/// Provides editable fields for API URL and API key, a git-sync
/// button with status feedback, and the current app version.
/// All mutations are observable so the view auto-updates.
@MainActor
@Observable
final class SettingsViewModel {

    // MARK: Published State

    /// The Hermes API URL — loaded from / saved to `UserDefaults`.
    var apiURL: String = ""

    /// The Hermes API key — loaded from / saved to the Keychain.
    var apiKey: String = ""

    /// Human-readable description of the last git sync result.
    var syncStatus: String = "Not yet synced"

    /// Whether a git sync is currently in progress.
    var isSyncing: Bool = false

    /// Whether a save operation is currently in flight.
    var isSaving: Bool = false

    /// Non-nil when there is a transient success/error message to show.
    var feedbackMessage: String? = nil

    /// The app version string from the bundle, or `—` if unavailable.
    let appVersion: String = {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }()

    // MARK: Dependencies

    private let keychainManager: KeychainManager
    private let gitSyncService: GitSyncService

    // MARK: Initialization

    /// Creates a new settings view model.
    ///
    /// - Parameters:
    ///   - keychainManager: The `KeychainManager` for reading / writing the API key.
    ///   - gitSyncService: The `GitSyncService` used to trigger git pulls.
    init(
        keychainManager: KeychainManager,
        gitSyncService: GitSyncService
    ) {
        self.keychainManager = keychainManager
        self.gitSyncService = gitSyncService
    }

    // MARK: - Load

    /// Populates `apiURL` and `apiKey` from persisted storage.
    ///
    /// Call this on appear so the form fields reflect whatever is stored.
    func load() async {
        // API URL from UserDefaults
        apiURL = UserDefaults.standard.string(forKey: "hermes_api_url") ?? ""

        // API key from Keychain
        do {
            apiKey = try await keychainManager.read() ?? ""
        } catch {
            feedbackMessage = "Failed to read API key: \(error.localizedDescription)"
        }
    }

    // MARK: - Save

    /// Persists the current `apiURL` and `apiKey` values.
    ///
    /// The URL is stored in `UserDefaults`; the key is stored in the
    /// Keychain. On success, a brief confirmation is shown.
    func save() async {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            feedbackMessage = "Both URL and API key are required."
            return
        }

        guard let url = URL(string: apiURL),
              url.scheme == "http" || url.scheme == "https" else {
            feedbackMessage = "Invalid URL. Must start with http:// or https://"
            return
        }

        isSaving = true
        feedbackMessage = nil

        do {
            try await keychainManager.save(key: apiKey)
            UserDefaults.standard.set(apiURL, forKey: "hermes_api_url")
            feedbackMessage = "Settings saved"
        } catch {
            feedbackMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    // MARK: - Git Sync

    /// Triggers a `git pull --ff-only` and updates `syncStatus`.
    func syncNow() async {
        isSyncing = true
        feedbackMessage = nil

        let result = await gitSyncService.sync()

        switch result {
        case .success(let output):
            syncStatus = "Synced: \(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))"
        case .noChanges:
            syncStatus = "Already up to date"
        case .failed(let error):
            syncStatus = "Sync failed: \(error)"
        case .gitNotFound:
            syncStatus = "Git not found on this system"
        }

        isSyncing = false
    }

    // MARK: - Feedback

    /// Clears the transient feedback message.
    func clearFeedback() {
        feedbackMessage = nil
    }
}
