import XCTest
@testable import HermesDesktop

// MARK: - SSEFrameParserTests

final class SSEFrameParserTests: XCTestCase {

    /// Feeds `chunks` through an `AsyncStream<UInt8>`, yielding a
    /// `Task.yield()` suspension between chunks so multi-chunk delivery is
    /// exercised the same way a real network read would arrive in pieces.
    private func makeByteStream(chunks: [[UInt8]]) -> AsyncStream<UInt8> {
        AsyncStream<UInt8> { continuation in
            Task {
                for chunk in chunks {
                    for byte in chunk {
                        continuation.yield(byte)
                    }
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }

    private func collectFrames(chunks: [[UInt8]], stopAfterFirst: Bool = false) async -> [SSEFrame] {
        var frames: [SSEFrame] = []
        try? await SSEFrameParser.run(bytes: makeByteStream(chunks: chunks)) { frame in
            frames.append(frame)
            return stopAfterFirst
        }
        return frames
    }

    private func collectFrames(_ text: String, chunkSize: Int? = nil) async -> [SSEFrame] {
        let bytes = Array(text.utf8)
        guard let chunkSize, chunkSize > 0, !bytes.isEmpty else {
            return await collectFrames(chunks: [bytes])
        }
        let chunks = stride(from: 0, to: bytes.count, by: chunkSize).map {
            Array(bytes[$0 ..< min($0 + chunkSize, bytes.count)])
        }
        return await collectFrames(chunks: chunks)
    }

    // MARK: - Blank Line Delimits Events

    func testBlankLineDelimitsEvents() async {
        let frames = await collectFrames("""
        event: foo
        data: one

        event: bar
        data: two

        """)

        XCTAssertEqual(frames, [
            SSEFrame(event: "foo", data: "one"),
            SSEFrame(event: "bar", data: "two"),
        ])
    }

    // MARK: - Multiple Data Lines Join

    func testMultipleDataLinesJoinWithNewline() async {
        let frames = await collectFrames("""
        event: foo
        data: line1
        data: line2

        """)

        XCTAssertEqual(frames, [SSEFrame(event: "foo", data: "line1\nline2")])
    }

    // MARK: - Split Across Chunks

    func testEventSplitAcrossChunks() async {
        let text = """
        event: foo
        data: hello world

        """
        // Chunk boundaries fall mid-line and mid-field, forcing the parser
        // to reassemble lines (and the frame) across independent deliveries.
        let frames = await collectFrames(text, chunkSize: 5)

        XCTAssertEqual(frames, [SSEFrame(event: "foo", data: "hello world")])
    }

    // MARK: - Comment Lines Ignored

    func testCommentLinesIgnored() async {
        let frames = await collectFrames("""
        : keep-alive
        event: foo
        data: bar

        """)

        XCTAssertEqual(frames, [SSEFrame(event: "foo", data: "bar")])
    }

    // MARK: - CRLF Line Endings

    func testCRLFLineEndings() async {
        let frames = await collectFrames("event: foo\r\ndata: bar\r\n\r\n")

        XCTAssertEqual(frames, [SSEFrame(event: "foo", data: "bar")])
    }

    // MARK: - Trailing Event Without Final Blank Line

    func testTrailingEventWithoutFinalBlankLineIsFlushed() async {
        let frames = await collectFrames("event: foo\ndata: bar")

        XCTAssertEqual(frames, [SSEFrame(event: "foo", data: "bar")])
    }

    // MARK: - Data-Only Frame

    func testDataOnlyFrameHasNilEvent() async {
        let frames = await collectFrames("""
        data: {"event": "foo"}

        """)

        XCTAssertEqual(frames, [SSEFrame(event: nil, data: #"{"event": "foo"}"#)])
    }

    // MARK: - Stop Halts Parsing

    func testOnFrameReturningTrueStopsParsing() async {
        let frames = await collectFrames(
            chunks: [Array("""
            event: one
            data: a

            event: two
            data: b

            """.utf8)],
            stopAfterFirst: true
        )

        XCTAssertEqual(frames, [SSEFrame(event: "one", data: "a")])
    }

    // MARK: - Empty Stream

    func testEmptyStreamProducesNoFrames() async {
        let frames = await collectFrames("")

        XCTAssertTrue(frames.isEmpty)
    }
}
