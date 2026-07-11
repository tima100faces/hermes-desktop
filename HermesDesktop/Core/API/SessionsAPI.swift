import Foundation

// MARK: - SessionInfo

/// Metadata for a single Hermes Sessions API session.
public struct SessionInfo: Decodable, Sendable {
    public let id: String
    public let title: String?

    public init(id: String, title: String?) {
        self.id = id
        self.title = title
    }
}

// MARK: - SessionEnvelope

/// Wraps the `{"object": "hermes.session", "session": {...}}` response shape
/// shared by create / get / update.
private struct SessionEnvelope: Decodable {
    let session: SessionInfo
}

// MARK: - SessionMessage

/// A single message row from `GET /api/sessions/{id}/messages`.
public struct SessionMessage: Decodable, Sendable {
    public let role: String
    public let content: String
    public let timestamp: Double

    public init(role: String, content: String, timestamp: Double) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - SessionMessagesEnvelope

private struct SessionMessagesEnvelope: Decodable {
    let data: [SessionMessage]
}

// MARK: - SessionDeleteResponse

private struct SessionDeleteResponse: Decodable {
    let deleted: Bool
}

// MARK: - SessionsAPIProtocol

/// Protocol abstraction over the Hermes Sessions API for testability.
public protocol SessionsAPIProtocol: Actor {
    func createSession() async throws -> SessionInfo
    func getSession(id: String) async throws -> SessionInfo
    func renameSession(id: String, title: String) async throws -> SessionInfo
    func deleteSession(id: String) async throws
    func getMessages(sessionId: String) async throws -> [SessionMessage]
    func streamChat(sessionId: String, input: String, instructions: String?, sessionKey: String?) async throws -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void)
}

// MARK: - SessionsAPI

/// High-level API for Hermes Sessions API — backs Sessions-backed `Chat`
/// conversations, as opposed to pinned, Runs-backed chats (migrated from
/// the old `Topic` entity), which stay on the older Runs API (`RunsAPI`)
/// unchanged.
public actor SessionsAPI: SessionsAPIProtocol {

    // MARK: - Properties

    private let apiClient: HermesAPIClient
    private let sseClient: SessionSSEClient

    // MARK: - Initialization

    public init(apiClient: HermesAPIClient, sseClient: SessionSSEClient = SessionSSEClient()) {
        self.apiClient = apiClient
        self.sseClient = sseClient
    }

    // MARK: - Create / Read / Rename / Delete

    /// Creates a new, empty session. Sends `POST /api/sessions`.
    public func createSession() async throws -> SessionInfo {
        let envelope: SessionEnvelope = try await apiClient.request(.sessionCreate)
        return envelope.session
    }

    /// Fetches a session's metadata. Sends `GET /api/sessions/{id}`.
    public func getSession(id: String) async throws -> SessionInfo {
        let envelope: SessionEnvelope = try await apiClient.request(.session(id: id))
        return envelope.session
    }

    /// Renames a session's title. Sends `PATCH /api/sessions/{id}`.
    public func renameSession(id: String, title: String) async throws -> SessionInfo {
        let envelope: SessionEnvelope = try await apiClient.request(.sessionUpdate(id: id, title: title))
        return envelope.session
    }

    /// Deletes a session. Sends `DELETE /api/sessions/{id}`.
    public func deleteSession(id: String) async throws {
        let _: SessionDeleteResponse = try await apiClient.request(.sessionDelete(id: id))
    }

    /// Fetches a session's message history. Sends
    /// `GET /api/sessions/{id}/messages`.
    public func getMessages(sessionId: String) async throws -> [SessionMessage] {
        let envelope: SessionMessagesEnvelope = try await apiClient.request(.sessionMessages(id: sessionId))
        return envelope.data
    }

    // MARK: - Chat Stream

    /// Sends a chat message and streams the assistant's turn.
    ///
    /// Sends `POST /api/sessions/{id}/chat/stream` and returns the
    /// translated, transport-agnostic `RunEvent` stream (see
    /// `SessionSSEClient` for the Sessions-dialect SSE mapping), plus a
    /// `cancel` closure — there's no documented stop endpoint for chat
    /// streams, so force-terminating the stream locally is the only way to
    /// stop reading further events.
    ///
    /// - Parameters:
    ///   - instructions: Project instructions, sent as the `instructions`
    ///     body field — layered as a system message on top of the agent's
    ///     personality (verified live, 2026-07-11). `nil` for chats outside
    ///     a project; the field is omitted from the request entirely rather
    ///     than sent as an empty string.
    ///   - sessionKey: A project's `X-Hermes-Session-Key`, sent as a header.
    ///     `nil` for chats outside a project — the header is omitted, same
    ///     as before this parameter existed.
    public func streamChat(sessionId: String, input: String, instructions: String? = nil, sessionKey: String? = nil) async throws -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void) {
        let base = apiClient.baseURL.absoluteString
        let path = "/api/sessions/\(sessionId)/chat/stream"
        let urlString = base.hasSuffix("/") ? base + path.dropFirst() : base + path
        guard let url = URL(string: urlString) else {
            throw APIError.unknown("Invalid chat/stream URL")
        }

        let token = try await apiClient.authenticationToken()
        return await sseClient.connect(url: url, token: token, input: input, instructions: instructions, sessionKey: sessionKey)
    }
}
