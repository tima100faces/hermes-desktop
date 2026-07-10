import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - SearchServiceTests

@MainActor
final class SearchServiceTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    let searchService = SearchService()

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Message.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    // MARK: Helpers

    private func insertMessage(_ content: String, role: Message.Role = .user) {
        let message = Message(content: content, role: role)
        modelContext.insert(message)
    }

    /// Saves the context and returns the inserted messages sorted by
    /// timestamp ascending for test assertions.
    private func saveAndFetchAll() throws -> [Message] {
        try modelContext.save()
        let descriptor = FetchDescriptor<Message>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Tests

    func testSearchFindsMessage() async throws {
        insertMessage("hello world", role: .user)
        try modelContext.save()

        let results = await searchService.search(query: "hello", in: modelContext)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.content, "hello world")
    }

    func testSearchEmptyQuery() async throws {
        insertMessage("something")
        try modelContext.save()

        let results = await searchService.search(query: "", in: modelContext)
        XCTAssertTrue(results.isEmpty)

        let whitespaceResults = await searchService.search(query: "   ", in: modelContext)
        XCTAssertTrue(whitespaceResults.isEmpty)
    }

    func testSearchCaseInsensitive() async throws {
        insertMessage("Hello World")
        try modelContext.save()

        let results = await searchService.search(query: "hello", in: modelContext)
        XCTAssertEqual(results.count, 1)
    }

    func testSearchSortOrder() async throws {
        // Messages are inserted in chronological order; older first.
        let msg1 = Message(content: "alpha", role: .user)
        msg1.timestamp = Date(timeIntervalSinceNow: -200)
        modelContext.insert(msg1)

        let msg2 = Message(content: "alpha", role: .user)
        msg2.timestamp = Date(timeIntervalSinceNow: -100)
        modelContext.insert(msg2)

        try modelContext.save()

        let results = await searchService.search(query: "alpha", in: modelContext)
        XCTAssertEqual(results.count, 2)

        // Newest first
        XCTAssertGreaterThan(
            results[0].timestamp,
            results[1].timestamp
        )
    }

    func testSearchLimit() async throws {
        // Insert 60 "alpha" messages
        for i in 0 ..< 60 {
            let msg = Message(content: "alpha", role: .user)
            msg.timestamp = Date(timeIntervalSinceNow: -Double(i))
            modelContext.insert(msg)
        }
        try modelContext.save()

        let results = await searchService.search(query: "alpha", in: modelContext)
        // Service caps at 50
        XCTAssertEqual(results.count, 50)
    }

    func testMockGeneratesMessages() {
        let messages = SearchService.mock(count: 100)
        XCTAssertEqual(messages.count, 100)

        // All should have non-empty content
        for msg in messages {
            XCTAssertFalse(msg.content.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertNotNil(Message.Role(rawValue: msg.role))
        }
    }
}
