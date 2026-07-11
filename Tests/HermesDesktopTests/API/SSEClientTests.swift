import XCTest
@testable import HermesDesktop

// MARK: - MockSSEURLProtocol

/// A `URLProtocol` subclass that intercepts all requests and returns canned SSE data.
final class MockSSEURLProtocol: URLProtocol {

    static var mockData: Data?
    static var mockStatusCode: Int = 200
    /// The most recent intercepted request — lets tests assert on headers
    /// and body, not just the response side.
    static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequest = request
        guard let data = Self.mockData else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: "1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - SSEClientTests

final class SSEClientTests: XCTestCase {

    override func tearDown() {
        MockSSEURLProtocol.mockData = nil
        MockSSEURLProtocol.mockStatusCode = 200
        MockSSEURLProtocol.capturedRequest = nil
    }

    /// Creates an `SSEClient` whose `URLSession` routes through `MockSSEURLProtocol`.
    private func makeClient() -> SSEClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: config)
        return SSEClient(session: session)
    }

    /// Collects all events from the stream returned by `SSEClient.connect(...)`.
    private func collectEvents(from client: SSEClient) async -> [RunEvent] {
        let url = URL(string: "https://example.com/stream")!
        let stream = await client.connect(url: url, token: "test-token")
        var events: [RunEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - Text Delta

    func testParseTextDelta() async {
        let sseData = """
        event: message.delta
        data: {"content": "Hello world"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .textDelta)
        XCTAssertEqual(events[0].content, "Hello world")
        XCTAssertNil(events[0].toolName)
        XCTAssertNil(events[0].toolInput)
        XCTAssertNil(events[0].error)
    }

    // MARK: - Multiple Data Lines

    /// Per the SSE spec, multiple `data:` lines within one event are joined
    /// with `\n` into a single value — never overwritten by the last one.
    func testParseEventWithMultipleDataLines() async {
        let sseData = """
        event: message.delta
        data: {"content":
        data: "joined value"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .textDelta)
        XCTAssertEqual(events[0].content, "joined value")
    }

    // MARK: - Tool Call

    func testParseToolCall() async {
        let sseData = """
        event: tool.call
        data: {"tool_name": "get_weather", "tool_input": "{\\"location\\": \\"NYC\\"}"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .toolCall)
        XCTAssertEqual(events[0].toolName, "get_weather")
        XCTAssertEqual(events[0].toolInput, #"{"location": "NYC"}"#)
        XCTAssertNil(events[0].content)
    }

    // MARK: - Tool Result

    func testParseToolResult() async {
        let sseData = """
        event: tool.result
        data: {"tool_name": "get_weather", "tool_output": "72°F, sunny"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .toolResult)
        XCTAssertEqual(events[0].toolName, "get_weather")
        XCTAssertEqual(events[0].toolOutput, "72°F, sunny")
        XCTAssertNil(events[0].content)
    }

    // MARK: - Run Completed

    func testParseRunCompleted() async {
        let sseData = """
        event: run.completed
        data: {}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .runCompleted)
    }

    // MARK: - Run Failed

    func testParseRunFailed() async {
        let sseData = """
        event: run.failed
        data: {"error": "Model API quota exceeded"}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .runFailed)
        XCTAssertEqual(events[0].error, "Model API quota exceeded")
    }

    // MARK: - Multiple Events

    func testParseMultipleEvents() async {
        let sseData = """
        event: message.delta
        data: {"content": "Hello"}

        event: message.delta
        data: {"content": " world"}

        event: run.completed
        data: {}

        """.data(using: .utf8)!
        MockSSEURLProtocol.mockData = sseData

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].type, .textDelta)
        XCTAssertEqual(events[0].content, "Hello")
        XCTAssertEqual(events[1].type, .textDelta)
        XCTAssertEqual(events[1].content, " world")
        XCTAssertEqual(events[2].type, .runCompleted)
    }

    // MARK: - Empty Stream

    func testEmptyStream() async {
        MockSSEURLProtocol.mockData = Data()

        let client = makeClient()
        let events = await collectEvents(from: client)

        XCTAssertTrue(events.isEmpty)
    }
}
