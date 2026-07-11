import XCTest
@testable import HermesDesktop

// MARK: - SessionSSEClientTests
//
// Small smoke tests confirming the Sessions dialect wrapper maps its own
// event names correctly and benefits from the shared `SSEFrameParser` fix
// (blank-line event boundaries, joined `data:` lines). Full parsing-edge-case
// coverage lives in `SSEFrameParserTests`.

final class SessionSSEClientTests: XCTestCase {

    override func tearDown() {
        MockSSEURLProtocol.mockData = nil
        MockSSEURLProtocol.mockStatusCode = 200
    }

    private func makeClient() -> SessionSSEClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: config)
        return SessionSSEClient(session: session)
    }

    private func collectEvents(from client: SessionSSEClient) async -> [RunEvent] {
        let url = URL(string: "https://example.com/api/sessions/abc/chat/stream")!
        let (stream, _) = await client.connect(url: url, token: "test-token", input: "hi")
        var events: [RunEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - Assistant Delta

    func testParseAssistantDelta() async {
        let sseData = """
        event: assistant.delta
        data: {"delta": "Hello world"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let events = await collectEvents(from: makeClient())

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .textDelta)
        XCTAssertEqual(events[0].content, "Hello world")
    }

    // MARK: - Tool Started (preview → toolInput)

    func testParseToolStartedUsesPreviewAsToolInput() async {
        let sseData = """
        event: tool.started
        data: {"tool_name": "shell", "preview": "echo hello"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let events = await collectEvents(from: makeClient())

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .toolCall)
        XCTAssertEqual(events[0].toolName, "shell")
        XCTAssertEqual(events[0].toolInput, "echo hello")
    }

    // MARK: - Run Completed

    func testParseRunCompleted() async {
        let sseData = """
        event: run.completed
        data: {}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let events = await collectEvents(from: makeClient())

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .runCompleted)
    }

    // MARK: - Blank-Line Boundaries + Joined Data Lines (the shared fix)

    func testMultipleEventsWithMultiLineDataStayDistinct() async {
        let sseData = """
        event: assistant.delta
        data: {"delta":
        data: "joined value"}

        event: assistant.delta
        data: {"delta": " world"}

        event: run.completed
        data: {}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let events = await collectEvents(from: makeClient())

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].type, .textDelta)
        XCTAssertEqual(events[0].content, "joined value")
        XCTAssertEqual(events[1].type, .textDelta)
        XCTAssertEqual(events[1].content, " world")
        XCTAssertEqual(events[2].type, .runCompleted)
    }
}
