import Foundation

// MARK: - RunResponse

/// Response from creating a new agent run.
public struct RunResponse: Decodable, Sendable {
    /// The unique identifier for the run.
    public let runId: String

    /// The initial status (typically `"started"`).
    public let status: String

    public enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }

    public init(runId: String, status: String) {
        self.runId = runId
        self.status = status
    }
}

// MARK: - UsageInfo

/// Token usage information returned with a completed run.
public struct UsageInfo: Decodable, Sendable {
    /// Number of input tokens consumed.
    public let inputTokens: Int

    /// Number of output tokens generated.
    public let outputTokens: Int

    /// Total tokens consumed (input + output).
    public let totalTokens: Int

    public enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

// MARK: - RunStatus

/// Current status of a Hermes agent run.
public struct RunStatus: Decodable, Sendable {
    /// The unique identifier for the run.
    public let runId: String

    /// The run status: `"started"`, `"in_progress"`, `"completed"`, `"failed"`, or `"cancelled"`.
    public let status: String

    /// Optional final output text (present when `status` is `"completed"`).
    public let output: String?

    /// Optional token usage information (present when `status` is `"completed"`).
    public let usage: UsageInfo?

    public enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case output
        case usage
    }

    public init(runId: String, status: String, output: String?, usage: UsageInfo?) {
        self.runId = runId
        self.status = status
        self.output = output
        self.usage = usage
    }
}

// MARK: - RunsAPIProtocol

/// Protocol abstraction over the Hermes Runs API for testability.
///
/// Conforming types must be `Actor`-isolated for Swift 6 concurrency.
public protocol RunsAPIProtocol: Actor {
    /// Creates a new agent run.
    /// - Parameters:
    ///   - input: The input text / prompt for the agent.
    ///   - conversation: An optional conversation identifier.
    /// - Returns: A `RunResponse` containing the new `runId` and initial status.
    /// - Throws: `APIError` or a transport error.
    func createRun(input: String, conversation: String?) async throws -> RunResponse

    /// Opens an SSE stream of events for a run.
    /// - Parameter runId: The ID of the run to stream.
    /// - Returns: An unbounded `AsyncStream<RunEvent>`.
    func streamEvents(runId: String) async -> AsyncStream<RunEvent>

    /// Stops a running agent.
    /// - Parameter runId: The ID of the run to stop.
    /// - Throws: `APIError` or a transport error.
    func stopRun(runId: String) async throws
}

// MARK: - RunsAPI

/// High-level API for creating and managing Hermes agent runs.
///
/// Provides create / stream / status / stop operations on top of
/// `HermesAPIClient` (REST) and `SSEClient` (SSE streaming).
///
/// All methods are actor-isolated for Swift 6 strict concurrency. Response
/// and request types are `Sendable`.
///
/// ## Usage
///
/// ```swift
/// let runs = RunsAPI(apiClient: client)
/// let response = try await runs.createRun(input: "Hello", conversation: "conv_123")
/// let stream = await runs.streamEvents(runId: response.runId)
/// for await event in stream {
///     // handle event
/// }
/// ```
public actor RunsAPI: RunsAPIProtocol {

    // MARK: - Properties

    /// The underlying Hermes REST API client.
    private let apiClient: HermesAPIClient

    /// The SSE stream client used for event streaming.
    private let sseClient: SSEClient

    // MARK: - Initialization

    /// Creates a new `RunsAPI` instance.
    ///
    /// - Parameters:
    ///   - apiClient: The `HermesAPIClient` used for REST API calls.
    ///   - sseClient: The `SSEClient` used for SSE streaming.
    ///                Defaults to a fresh `SSEClient()`.
    public init(apiClient: HermesAPIClient, sseClient: SSEClient = SSEClient()) {
        self.apiClient = apiClient
        self.sseClient = sseClient
    }

    // MARK: - Create Run

    /// Creates a new agent run.
    ///
    /// Sends `POST /v1/runs` with the input text and an optional conversation
    /// identifier for context.
    ///
    /// - Parameters:
    ///   - input: The input text / prompt for the agent.
    ///   - conversation: An optional conversation identifier. Pass `nil` when
    ///                   starting a fresh conversation.
    /// - Returns: A `RunResponse` containing the new `runId` and initial status.
    /// - Throws: `APIError` or a transport error.
    public func createRun(input: String, conversation: String?) async throws -> RunResponse {
        try await apiClient.request(
            .createRun(input: input, conversation: conversation ?? "")
        )
    }

    // MARK: - Stream Events

    /// Opens an SSE stream of events for a run.
    ///
    /// The returned `AsyncStream` yields `RunEvent` values as they arrive from
    /// the server and finishes automatically when the run completes, fails, or
    /// the caller cancels the iteration.
    ///
    /// - Parameter runId: The ID of the run to stream.
    /// - Returns: An unbounded `AsyncStream<RunEvent>`.
    public func streamEvents(runId: String) async -> AsyncStream<RunEvent> {
        // Construct SSE URL properly with multi-segment path (e.g. /v1/runs/{id}/events)
        let endpoint = HermesAPIClient.Endpoint.runEvents(runId: runId)
        let streamURL = URL(string: endpoint.path, relativeTo: apiClient.baseURL)!

        // Retrieve the Bearer token. If this fails, return an empty stream.
        let token: String
        do {
            token = try await apiClient.authenticationToken()
        } catch {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return await sseClient.connect(url: streamURL, token: token)
    }

    // MARK: - Get Status

    /// Polls the current status of a run (non-streaming).
    ///
    /// Sends `GET /v1/runs/{runId}` and returns the run's current state,
    /// optional output, and token usage.
    ///
    /// - Parameter runId: The ID of the run to query.
    /// - Returns: A `RunStatus` with the current state.
    /// - Throws: `APIError` or a transport error.
    public func getStatus(runId: String) async throws -> RunStatus {
        try await apiClient.request(.runStatus(runId: runId))
    }

    // MARK: - Stop Run

    /// Stops a running agent.
    ///
    /// Sends `POST /v1/runs/{runId}/stop` to request cancellation. The server
    /// will transition the run to a `"cancelled"` status.
    ///
    /// - Parameter runId: The ID of the run to stop.
    /// - Throws: `APIError` or a transport error.
    public func stopRun(runId: String) async throws {
        let _: StopRunResponse = try await apiClient.request(.stopRun(runId: runId))
    }
}

// MARK: - StopRunResponse

/// Minimal response type for the stop-run endpoint.
///
/// The stop endpoint returns a JSON body (e.g. `{"status": "cancelled"}`)
/// which we decode but discard, since the caller is only interested in
/// knowing the request succeeded without an error.
private struct StopRunResponse: Decodable, Sendable {
    let status: String
}
