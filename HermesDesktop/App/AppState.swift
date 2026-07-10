// MARK: - AppState
//
// Global application state — DI container and lifecycle.

import SwiftUI
import Observation

// MARK: - AppState

/// The single source of truth for app-level dependencies and configuration.
///
/// Owns the long-lived instances of `KeychainManager`, `GitSyncService`,
/// `HermesAPIClient`, and `RunsAPI`, and determines whether the user sees
/// the Onboarding flow or the main ContentView based on stored credentials.
///
/// ## Lifecycle
/// 1. `HermesDesktopApp` creates an `@State private var appState = AppState()`.
/// 2. `initialize()` is called after onboarding completes, or automatically
///    if credentials already exist.
/// 3. When `isConfigured` becomes `true`, the main content is shown.
@MainActor
@Observable
final class AppState {

    // MARK: - Published State

    /// Whether the user has configured API credentials.
    ///
    /// When `false`, the onboarding screen is shown.
    var isConfigured: Bool = false

    /// The Hermes API client — set after successful initialisation.
    /// `nil` when not configured.
    private(set) var apiClient: HermesAPIClient?

    /// The Runs API — set after successful initialisation.
    /// `nil` when not configured.
    private(set) var runsAPI: RunsAPI?

    // MARK: - Dependencies (always alive)

    /// Manages API key persistence in the macOS Keychain.
    let keychainManager: KeychainManager

    /// Performs `git pull --ff-only` in `~/Projects/agents-hub`.
    let gitSyncService: GitSyncService

    // MARK: - Initialization

    init() {
        self.keychainManager = KeychainManager()
        self.gitSyncService = GitSyncService()
    }

    /// Attempts to read stored credentials and bootstrap the API clients.
    ///
    /// Call this on launch **and** after the onboarding flow completes.
    /// If the Keychain contains an API key and `UserDefaults` has a saved
    /// API URL, `HermesAPIClient` and `RunsAPI` are created and
    /// `isConfigured` is set to `true`.
    func initialize() async {
        // --- Read stored credentials -------------------------------------------
        do {
            guard (try await keychainManager.read()) != nil else {
                // No key stored — stay on onboarding.
                return
            }
        } catch {
            // Keychain read failed — stay on onboarding.
            return
        }

        guard let urlString = UserDefaults.standard.string(forKey: "hermes_api_url"),
              let url = URL(string: urlString) else {
            // No URL stored — stay on onboarding.
            return
        }

        // --- Bootstrap API clients ---------------------------------------------
        let client = HermesAPIClient(baseURL: url, keychainManager: keychainManager)
        let sseClient = SSEClient()
        let runs = RunsAPI(apiClient: client, sseClient: sseClient)

        self.apiClient = client
        self.runsAPI = runs
        self.isConfigured = true

        // --- Fire-and-forget git sync ------------------------------------------
        Task.detached { [gitSyncService] in
            let _ = await gitSyncService.sync()
        }
    }
}
