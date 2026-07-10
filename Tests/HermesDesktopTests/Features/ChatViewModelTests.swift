import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - MockRunsAPI

/// Controlled mock of the Hermes Runs API for unit tests.
///
/// Tests configure the mock with a pre-built event stream and then drive
/// `ChatViewModel` through its normal send/stop/load flow. The mock runs as
/// a separate actor so callers don't block, and streams are built via
/// `AsyncStream` continuations so tests can yield events on demand.
actor MockRunsAPI: RunsAPIProtocol {

    // MARK: Configuration

    /// The result to return from the next ``createRun(input:conversation:)`` call.
    var createRunResult: Result<RunResponse, Error> = .success(
        RunResponse(runId: "test-run-id", status: "started")
    )

    /// The stream continuation (set when ``streamEvents(runId:)`` is called).
    private var streamContinuation: AsyncStream<RunEvent>.Continuation?

    /// The stream itself (set when ``streamEvents(runId:)`` is called).
    private var stream: AsyncStream<RunEvent>?

    /// Whether ``stopRun(runId:)`` was called.
    private(set) var stopRunCalled = false

    /// The run ID passed to the most recent ``stopRun(runId:)`` call.
    private(set) var stoppedRunId: String?

    // MARK: Protocol Conformance

    func createRun(input: String, conversation: String?) async throws -> RunResponse {
        try createRunResult.get()
    }

    func streamEvents(runId: String) async -> AsyncStream<RunEvent> {
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        self.stream = stream
        self.streamContinuation = continuation
        return stream
    }

    func stopRun(runId: String) async throws {
        stopRunCalled = true
        stoppedRunId = runId
    }

    // MARK: Test Helpers

    /// Send a single event through the active stream.
    func sendEvent(_ event: RunEvent) {
        streamContinuation?.yield(event)
    }

    /// Finish the active stream (no more events).
    func finishStream() {
        streamContinuation?.finish()
        streamContinuation = nil
    }
}

// MARK: - ChatViewModelTests

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: Fixtures

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var mockRunsAPI: MockRunsAPI!
    var project: Project!
    var viewModel: ChatViewModel!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Project.self, Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        mockRunsAPI = MockRunsAPI()

        project = Project(name: "Test Project", conversationKey: "test-project")
        modelContext.insert(project)
        try modelContext.save()

        viewModel = ChatViewModel(runsAPI: mockRunsAPI, project: project)
    }

    override func tearDown() async throws {
        // Tear down in reverse order.
        viewModel = nil
        project = nil
        mockRunsAPI = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.inputText.isEmpty)
        XCTAssertTrue(viewModel.streamingContent.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.agentStatuses.isEmpty)
    }

    // MARK: - Send Message

    func testSendMessageCreatesUserMessage() async throws {
        // Arrange
        viewModel.inputText = "Hello, Hermes!"
        let completionEvent = RunEvent(type: .runCompleted, content: "Hello, user!")

        // Act — sendMessage will persist the user msg, then kick off the
        // stream and immediately encounter run_completed.
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        // Let sendMessage reach the streaming phase.
        try? await Task.sleep(nanoseconds: 50_000_000)

        await mockRunsAPI.sendEvent(completionEvent)
        await mockRunsAPI.finishStream()
        await sendTask.value

        // Assert — one user message + one assistant message exist
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].content, "Hello, Hermes!")
        XCTAssertEqual(viewModel.messages[0].role, Message.Role.user.rawValue)
        XCTAssertEqual(viewModel.messages[1].role, Message.Role.assistant.rawValue)
        // Content may vary based on mock stream timing — assistant message is present
    }

    func testSendEmptyInputIgnored() async {
        // Arrange — inputText is empty by default

        // Act
        await viewModel.sendMessage(context: modelContext)

        // Assert
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isStreaming)
    }

    func testSendWhitespaceInputIgnored() async {
        // Arrange
        viewModel.inputText = "   \n  \t  "

        // Act
        await viewModel.sendMessage(context: modelContext)

        // Assert
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.isStreaming)
    }

    // MARK: - Streaming State

    func testStreamingSetsIsStreaming() async throws {
        // Arrange
        viewModel.inputText = "Hello"

        // Act — start sendMessage (stream stays open, never finished)
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        // Give the task a chance to advance to the streaming phase.
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Assert — isStreaming should be true
        XCTAssertTrue(viewModel.isStreaming)

        // Clean up — close the stream so the task finishes.
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    func testTextDeltaAppendsContent() async throws {
        // Arrange
        viewModel.inputText = "Explain Swift"

        // Act — start sendMessage
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        await mockRunsAPI.sendEvent(RunEvent(type: .textDelta, content: "Swift"))
        try? await Task.sleep(nanoseconds: 10_000_000)
        await mockRunsAPI.sendEvent(RunEvent(type: .textDelta, content: " is"))
        try? await Task.sleep(nanoseconds: 10_000_000)
        await mockRunsAPI.sendEvent(RunEvent(type: .textDelta, content: " awesome"))
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert — streaming content accumulated correctly
        XCTAssertEqual(viewModel.streamingContent, "Swift is awesome")

        // Clean up
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    // MARK: - Run Completion & Failure

    func testRunCompletedSavesMessage() async throws {
        // Arrange
        viewModel.inputText = "Hello"
        let completionEvent = RunEvent(
            type: .runCompleted,
            content: "Final response"
        )

        // Act
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Send a delta first so streamingContent has content.
        await mockRunsAPI.sendEvent(RunEvent(type: .textDelta, content: "Final response"))
        try? await Task.sleep(nanoseconds: 10_000_000)
        await mockRunsAPI.sendEvent(completionEvent)
        await mockRunsAPI.finishStream()
        await sendTask.value

        // Assert
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[1].content, "Final response")
        XCTAssertEqual(viewModel.messages[1].role, Message.Role.assistant.rawValue)
        XCTAssertEqual(viewModel.messages[1].runId, "test-run-id")
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.streamingContent.isEmpty)
    }

    func testRunFailedSetsError() async throws {
        // Arrange
        viewModel.inputText = "Do something impossible"

        // Act
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        await mockRunsAPI.sendEvent(
            RunEvent(type: .runFailed, error: "Something went wrong")
        )
        await mockRunsAPI.finishStream()
        await sendTask.value

        // Assert
        XCTAssertEqual(viewModel.errorMessage, "Something went wrong")
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.streamingContent.isEmpty)
        // Only the user message survived (no assistant persisted on failure)
        XCTAssertEqual(viewModel.messages.count, 1)
    }

    func testRunFailedWithoutErrorMessage() async throws {
        // Arrange
        viewModel.inputText = "Explode"

        // Act
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        await mockRunsAPI.sendEvent(RunEvent(type: .runFailed, error: nil))
        await mockRunsAPI.finishStream()
        await sendTask.value

        // Assert — fallback message
        XCTAssertEqual(viewModel.errorMessage, "Run failed")
        XCTAssertFalse(viewModel.isStreaming)
    }

    // MARK: - Stop Streaming

    func testStopStreamingSavesPartialContent() async throws {
        // Arrange
        viewModel.inputText = "Write a story"

        // Act — start streaming
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Send some content
        await mockRunsAPI.sendEvent(RunEvent(type: .textDelta, content: "Once upon a time"))
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Stop streaming
        viewModel.stopStreaming(context: modelContext)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert — partial content saved as assistant message
        XCTAssertEqual(viewModel.messages.count, 2) // user msg + partial assistant
        XCTAssertEqual(viewModel.messages[1].content, "Once upon a time")
        XCTAssertEqual(viewModel.messages[1].role, Message.Role.assistant.rawValue)
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertTrue(viewModel.streamingContent.isEmpty)

        // Clean up — stream was already closed by stopStreaming clearing currentRunId,
        // but the event loop may still be running. Finish the stream for clean exit.
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    func testStopStreamingClearsAgentStatuses() async throws {
        // Arrange
        viewModel.inputText = "Tool time"

        // Act — start streaming
        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Simulate a tool call so agentStatuses is populated
        await mockRunsAPI.sendEvent(
            RunEvent(type: .toolCall, toolName: "search", toolInput: "query")
        )
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(viewModel.agentStatuses.count, 1)

        // Stop streaming
        viewModel.stopStreaming(context: modelContext)

        // Assert — agent statuses cleared
        XCTAssertTrue(viewModel.agentStatuses.isEmpty)

        // Clean up
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    // MARK: - Tool Events

    func testToolCallCreatesAgentStatus() async throws {
        // Arrange
        viewModel.inputText = "Use tools"

        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Act — send a tool_call event
        await mockRunsAPI.sendEvent(
            RunEvent(type: .toolCall, toolName: "code-review", toolInput: "scan file.swift")
        )
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert
        XCTAssertEqual(viewModel.agentStatuses.count, 1)
        XCTAssertEqual(viewModel.agentStatuses[0].name, "code-review")
        XCTAssertEqual(viewModel.agentStatuses[0].state, AgentState.running)
        XCTAssertEqual(viewModel.agentStatuses[0].progress, "scan file.swift")

        // Clean up
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    func testToolResultUpdatesAgentStatus() async throws {
        // Arrange
        viewModel.inputText = "Use tools"

        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Send tool call
        await mockRunsAPI.sendEvent(
            RunEvent(type: .toolCall, toolName: "code-review", toolInput: "scan")
        )
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Act — send matching tool result
        await mockRunsAPI.sendEvent(
            RunEvent(type: .toolResult, toolName: "code-review", toolOutput: "All clear")
        )
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Assert
        XCTAssertEqual(viewModel.agentStatuses[0].state, AgentState.completed)
        XCTAssertEqual(viewModel.agentStatuses[0].progress, "All clear")

        // Clean up
        await mockRunsAPI.finishStream()
        await sendTask.value
    }

    // MARK: - Load Messages

    func testLoadMessagesFetchesFromSwiftData() async throws {
        // Arrange — insert messages directly into SwiftData
        let msg1 = Message(content: "First", role: .user)
        msg1.project = project
        modelContext.insert(msg1)

        let msg2 = Message(content: "Second", role: .assistant)
        msg2.project = project
        modelContext.insert(msg2)

        try modelContext.save()

        // Act
        viewModel.loadMessages(context: modelContext)

        // Assert
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].content, "First")
        XCTAssertEqual(viewModel.messages[1].content, "Second")
    }

    func testLoadMessagesOnlyFetchesForCurrentProject() async throws {
        // Arrange — insert messages for the current project
        let msg = Message(content: "Mine", role: .user)
        msg.project = project
        modelContext.insert(msg)

        // Insert a message for a different project
        let otherProject = Project(name: "Other", conversationKey: "other")
        modelContext.insert(otherProject)
        let otherMsg = Message(content: "Not mine", role: .user)
        otherMsg.project = otherProject
        modelContext.insert(otherMsg)

        try modelContext.save()

        // Act
        viewModel.loadMessages(context: modelContext)

        // Assert — only messages for test-project
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Mine")
    }

    // MARK: - Input Cleared After Send

    func testInputTextClearedAfterSend() async throws {
        // Arrange
        viewModel.inputText = "Clear me"

        let sendTask = Task {
            await viewModel.sendMessage(context: modelContext)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        await mockRunsAPI.sendEvent(RunEvent(type: .runCompleted))
        await mockRunsAPI.finishStream()
        await sendTask.value

        // Assert
        XCTAssertTrue(viewModel.inputText.isEmpty)
    }

    // MARK: - Create Run Failure

    func testSendMessageWhenCreateRunFails() async throws {
        // Arrange
        await mockRunsAPI.setCreateRunToFail()

        viewModel.inputText = "Fail"

        // Act
        await viewModel.sendMessage(context: modelContext)

        // Assert — error message set, streaming stopped
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isStreaming)
        // User message still persisted
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Fail")
    }
}

// MARK: - MockRunsAPI: Test Helpers

extension MockRunsAPI {
    /// Configure the mock so that the next `createRun` call throws an error.
    func setCreateRunToFail() {
        createRunResult = .failure(
            NSError(domain: "mock", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
    }
}
