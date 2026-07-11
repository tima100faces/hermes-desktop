import XCTest
import SwiftData
@testable import HermesDesktop

// MARK: - SessionsConversationServiceTests
//
// Focused on what `SessionsConversationService.send` threads through to
// the Sessions API based on `chat.project` — the low-level header/body
// construction itself is covered in `SessionSSEClientTests`.
//
// `MockSessionsAPI` is defined in `SidebarViewModelTests.swift` and shared
// across the test target.

@MainActor
final class SessionsConversationServiceTests: XCTestCase {

    var mockSessionsAPI: MockSessionsAPI!

    override func setUp() async throws {
        mockSessionsAPI = MockSessionsAPI()
    }

    override func tearDown() async throws {
        mockSessionsAPI = nil
    }

    func testSendWithoutProjectOmitsInstructionsAndSessionKey() async throws {
        // Arrange
        let chat = Chat(sessionId: "session-1", title: "No Project")
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        // Act
        _ = try await service.send(input: "hello")

        // Assert
        let call = await mockSessionsAPI.lastStreamChatCall
        XCTAssertEqual(call?.input, "hello")
        XCTAssertNil(call?.instructions)
        XCTAssertNil(call?.sessionKey)
    }

    func testSendWithProjectPassesInstructionsAndSessionKey() async throws {
        // Arrange
        let project = Project(name: "P")
        project.instructions = "Be concise."
        let chat = Chat(sessionId: "session-1", title: "In Project")
        chat.project = project
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        // Act
        _ = try await service.send(input: "hello")

        // Assert
        let call = await mockSessionsAPI.lastStreamChatCall
        XCTAssertEqual(call?.instructions, "Be concise.")
        XCTAssertEqual(call?.sessionKey, project.sessionKey)
    }

    func testSendWithProjectEmptyInstructionsOmitsInstructionsField() async throws {
        // Arrange — an untouched project's instructions default to ""
        let project = Project(name: "P")
        let chat = Chat(sessionId: "session-1", title: "In Project")
        chat.project = project
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        // Act
        _ = try await service.send(input: "hello")

        // Assert — omitted (nil), not sent as an empty string
        let call = await mockSessionsAPI.lastStreamChatCall
        XCTAssertNil(call?.instructions)
        // The session key is still sent — it's independent of instructions.
        XCTAssertEqual(call?.sessionKey, project.sessionKey)
    }

    func testSendWithProjectWhitespaceOnlyInstructionsOmitsInstructionsField() async throws {
        // Arrange
        let project = Project(name: "P")
        project.instructions = "   \n  "
        let chat = Chat(sessionId: "session-1", title: "In Project")
        chat.project = project
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        // Act
        _ = try await service.send(input: "hello")

        // Assert
        let call = await mockSessionsAPI.lastStreamChatCall
        XCTAssertNil(call?.instructions)
    }
}
