import SwiftUI
import Observation

// MARK: - OnboardingViewModel

/// ViewModel for the initial connection/onboarding screen.
///
/// Manages API URL and key input, saves credentials to the Keychain,
/// performs a health-check against the Hermes API, and signals success
/// so the parent view can navigate to the main app.
@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: Published State

    /// The API URL text entered by the user.
    var apiURL: String = ""

    /// The API key text entered by the user.
    var apiKey: String = ""

    /// Whether a connect attempt is in flight.
    var isLoading: Bool = false

    /// Non-nil when an error should be displayed to the user.
    var errorMessage: String?

    /// Set to `true` after a successful health check — drives navigation
    /// in the parent view via `onChange(of: isConnected)`.
    var isConnected: Bool = false

    // MARK: Dependencies

    private let keychainManager: KeychainManager

    // MARK: Initialization

    /// Creates a new onboarding view model.
    ///
    /// - Parameter keychainManager: The `KeychainManager` used to persist
    ///   the API key. Defaults to a fresh instance, which is fine for
    ///   previews and production alike.
    init(keychainManager: KeychainManager = KeychainManager()) {
        self.keychainManager = keychainManager
    }

    // MARK: Intents

    /// Attempts to connect to the Hermes API.
    ///
    /// 1. Validates the URL and key are present and well-formed.
    /// 2. Persists the key to the Keychain.
    /// 3. Performs a `GET /v1/health` request.
    /// 4. On success, saves the URL to `UserDefaults` and sets
    ///    `isConnected = true`.
    func connect() async {
        guard !apiURL.isEmpty, !apiKey.isEmpty else {
            errorMessage = "Please enter both URL and API key"
            return
        }

        guard let url = URL(string: apiURL),
              url.scheme == "http" || url.scheme == "https" else {
            errorMessage = "Invalid URL. Must start with http:// or https://"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Save the API key to the Keychain first so that the
            // HermesAPIClient can read it for the health-check request.
            try await keychainManager.save(key: apiKey)

            // Perform a typed health-check request.
            let client = HermesAPIClient(baseURL: url, keychainManager: keychainManager)

            struct HealthResponse: Decodable {
                let status: String
            }

            let response: HealthResponse = try await client.request(.health)

            if response.status == "ok" {
                // Persist the URL for subsequent launches.
                UserDefaults.standard.set(apiURL, forKey: "hermes_api_url")
                isConnected = true
            } else {
                errorMessage = "Server returned unexpected status: \"\(response.status)\""
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Dismisses the current error message.
    func clearError() {
        errorMessage = nil
    }
}
