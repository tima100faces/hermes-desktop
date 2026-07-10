import SwiftUI
import Observation

// MARK: - ConnectionMonitor
//
// Periodically pings `GET /v1/health` and publishes reachability for
// the sidebar status dot (docs/UI-SPEC.md §9).

@MainActor
@Observable
final class ConnectionMonitor {

    // MARK: - Status

    enum Status {
        /// No check has completed yet.
        case unknown
        /// Last health check returned 2xx.
        case online
        /// Last health check failed (network error or non-2xx).
        case offline
    }

    /// The most recent reachability result.
    private(set) var status: Status = .unknown

    // MARK: - Dependencies

    private let apiClient: HermesAPIClient
    private var pollTask: Task<Void, Never>?

    // MARK: - Initialization

    init(apiClient: HermesAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Polling

    /// Starts the polling loop. Safe to call repeatedly — restarts it.
    ///
    /// - Parameter interval: Delay between health checks (default 30s).
    func start(interval: Duration = .seconds(30)) {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let reachable = await self.apiClient.ping()
                if Task.isCancelled { return }
                self.status = reachable ? .online : .offline
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stops the polling loop.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
