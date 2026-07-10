import Foundation

// MARK: - HermesAPIClient

/// Actor-based HTTP client for the Hermes API.
///
/// Uses `URLSession` with Bearer token authentication via `KeychainManager`.
/// All network calls are actor-isolated for Swift 6 strict concurrency.
public actor HermesAPIClient {

    // MARK: - Properties

    /// Base URL for all API requests.
    public let baseURL: URL

    /// Keychain manager for reading the Bearer token.
    private let keychainManager: KeychainManager

    /// Shared URL session with a 30-second timeout.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates a new API client.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL for the Hermes API.
    ///   - keychainManager: A `KeychainManager` instance for token retrieval.
    ///   - session: A custom URLSession (defaults to a new session with 30s timeout).
    public init(baseURL: URL, keychainManager: KeychainManager, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.keychainManager = keychainManager

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Public API

    /// Returns the current Bearer token for authentication.
    ///
    /// Used by `RunsAPI` to pass a token to `SSEClient` for SSE streaming.
    /// - Returns: The stored Bearer token string.
    /// - Throws: `APIError.unauthorized` if no token is stored.
    public func authenticationToken() async throws -> String {
        guard let token = try await keychainManager.read() else {
            throw APIError.unauthorized
        }
        return token
    }

    /// Performs a typed API request.
    ///
    /// - Parameter endpoint: The `Endpoint` describing the request.
    /// - Returns: A decoded `T` value from the JSON response body.
    /// - Throws: `APIError` for HTTP errors, transport errors, or decoding failures.
    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let urlRequest = try await buildRequest(from: endpoint)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw APIError(urlError: urlError)
        } catch {
            throw APIError.networkError(underlying: error)
        }

        try validate(response: response, data: data)

        return try decode(T.self, from: data)
    }

    // MARK: - Request Building

    /// Assembles a `URLRequest` from an `Endpoint`, injecting the Bearer token.
    ///
    /// - Parameter endpoint: The endpoint descriptor.
    /// - Returns: A configured `URLRequest`.
    /// - Throws: `APIError.unauthorized` if no token is stored in the Keychain,
    ///           or a `KeychainError` if the Keychain read fails.
    private func buildRequest(from endpoint: Endpoint) async throws -> URLRequest {
        guard let token = try await keychainManager.read() else {
            throw APIError.unauthorized
        }

        let url = baseURL.appendingPathComponent(endpoint.path)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = endpoint.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 30

        if let body = endpoint.body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
        }

        return urlRequest
    }

    // MARK: - Response Validation

    /// Validates the HTTP response, throwing `APIError` for non-success status codes.
    ///
    /// - Parameters:
    ///   - response: The `URLResponse` from the session.
    ///   - data: The raw response data (unused here, but available for future
    ///           inspection such as error-body parsing).
    /// - Throws: An `APIError` mapped from the HTTP status code.
    private func validate(response: URLResponse, data _: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown("Unexpected non-HTTP response.")
        }

        if let error = APIError(httpStatusCode: httpResponse.statusCode) {
            throw error
        }
    }

    // MARK: - Decoding

    /// Decodes the response data into the requested type using `.iso8601` date strategy.
    ///
    /// - Parameters:
    ///   - type: The expected Swift type.
    ///   - data: Raw JSON data from the response.
    /// - Returns: A decoded instance of `T`.
    /// - Throws: `APIError.decodingError` on JSON parse failure.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(underlying: error)
        }
    }
}

// MARK: - Endpoint

extension HermesAPIClient {

    /// Describes an API endpoint — path, HTTP method, and optional body payload.
    ///
    /// Each case maps to a Hermes API route:
    /// - `health` → `GET /v1/health`
    /// - `capabilities` → `GET /v1/capabilities`
    /// - `createRun` → `POST /v1/runs`
    /// - `runStatus` → `GET /v1/runs/{runId}`
    /// - `runEvents` → `GET /v1/runs/{runId}/events`
    /// - `stopRun` → `POST /v1/runs/{runId}/stop`
    public enum Endpoint {
        /// Check API health.
        case health

        /// List available capabilities / models.
        case capabilities

        /// Create a new run with the given input and conversation context.
        case createRun(input: String, conversation: String)

        /// Poll the status of an existing run.
        case runStatus(runId: String)

        /// Stream events for an existing run.
        case runEvents(runId: String)

        /// Request cancellation of a running run.
        case stopRun(runId: String)

        /// The URL path component (relative to `baseURL`).
        public var path: String {
            switch self {
            case .health:
                return "/v1/health"
            case .capabilities:
                return "/v1/capabilities"
            case .createRun:
                return "/v1/runs"
            case .runStatus(let runId):
                return "/v1/runs/\(runId)"
            case .runEvents(let runId):
                return "/v1/runs/\(runId)/events"
            case .stopRun(let runId):
                return "/v1/runs/\(runId)/stop"
            }
        }

        /// The HTTP method for this endpoint.
        public var method: String {
            switch self {
            case .health, .capabilities, .runStatus, .runEvents:
                return "GET"
            case .createRun, .stopRun:
                return "POST"
            }
        }

        /// Optional JSON body data. Returns `nil` for GET requests.
        public var body: Data? {
            switch self {
            case .createRun(let input, let conversation):
                let payload: [String: String] = [
                    "input": input,
                    "conversation": conversation,
                ]
                return try? JSONSerialization.data(withJSONObject: payload)
            default:
                return nil
            }
        }
    }
}
