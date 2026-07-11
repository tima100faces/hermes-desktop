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

    // MARK: - autoTitle(from:) — pure truncation logic

    func testAutoTitleShortMessageIsUnchanged() {
        XCTAssertEqual(SessionsConversationService.autoTitle(from: "Fix the login bug"), "Fix the login bug")
    }

    func testAutoTitleExactly40CharactersIsUnchanged() {
        let text = String(repeating: "a", count: 40)
        XCTAssertEqual(SessionsConversationService.autoTitle(from: text), text)
    }

    func testAutoTitleTruncatesAtWordBoundaryWithEllipsis() {
        let text = "What is the best way to learn Rust programming as a beginner"
        // First 40 chars: "What is the best way to learn Rust prog" — cuts back to the last space.
        XCTAssertEqual(SessionsConversationService.autoTitle(from: text), "What is the best way to learn Rust…")
    }

    func testAutoTitleHardCutsWhenNoSpaceInWindow() {
        let text = String(repeating: "a", count: 60)
        let expected = String(repeating: "a", count: 40) + "…"
        XCTAssertEqual(SessionsConversationService.autoTitle(from: text), expected)
    }

    func testAutoTitleCollapsesWhitespaceAndNewlines() {
        XCTAssertEqual(SessionsConversationService.autoTitle(from: "Hello\n\nworld  \t there"), "Hello world there")
    }

    func testAutoTitlePureWhitespaceReturnsNil() {
        XCTAssertNil(SessionsConversationService.autoTitle(from: "   \n\t  "))
    }

    // MARK: - autoTitleIfNeeded — guards and server round-trip

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Chat.self, Message.self, Project.self, configurations: config)
        return container.mainContext
    }

    func testAutoTitleIfNeededRenamesServerAndLocalTitle() async throws {
        let context = try makeContext()
        let chat = Chat(sessionId: "session-1", title: Chat.defaultTitle)
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        await service.autoTitleIfNeeded(from: "What is the best way to learn Rust programming", context: context)

        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertEqual(renamedIds, ["session-1"])
        XCTAssertEqual(chat.title, "What is the best way to learn Rust…")
        XCTAssertTrue(chat.hasAutoTitled)
    }

    func testAutoTitleIfNeededSkipsWhenAlreadyAutoTitled() async throws {
        let context = try makeContext()
        let chat = Chat(sessionId: "session-1", title: Chat.defaultTitle)
        chat.hasAutoTitled = true
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        await service.autoTitleIfNeeded(from: "hello", context: context)

        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertTrue(renamedIds.isEmpty)
        XCTAssertEqual(chat.title, Chat.defaultTitle)
    }

    func testAutoTitleIfNeededSkipsWhenTitleAlreadyChanged() async throws {
        // Simulates a manual rename landing between this chat's creation
        // and its first message being sent, even if hasAutoTitled hadn't
        // been set yet for some reason — the title check is the real guard.
        let context = try makeContext()
        let chat = Chat(sessionId: "session-1", title: "My Custom Title")
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        await service.autoTitleIfNeeded(from: "hello", context: context)

        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertTrue(renamedIds.isEmpty)
        XCTAssertEqual(chat.title, "My Custom Title")
    }

    func testAutoTitleIfNeededSkipsForWhitespaceOnlyMessage() async throws {
        let context = try makeContext()
        let chat = Chat(sessionId: "session-1", title: Chat.defaultTitle)
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        await service.autoTitleIfNeeded(from: "   \n  ", context: context)

        let renamedIds = await mockSessionsAPI.renamedSessionIds
        XCTAssertTrue(renamedIds.isEmpty)
        XCTAssertEqual(chat.title, Chat.defaultTitle)
        XCTAssertFalse(chat.hasAutoTitled)
    }

    func testAutoTitleIfNeededServerFailureResetsHasAutoTitledAndKeepsDefaultTitle() async throws {
        let context = try makeContext()
        await mockSessionsAPI.setRenameSessionToFail()
        let chat = Chat(sessionId: "session-1", title: Chat.defaultTitle)
        let service = SessionsConversationService(sessionsAPI: mockSessionsAPI, chat: chat)

        await service.autoTitleIfNeeded(from: "hello there", context: context)

        XCTAssertEqual(chat.title, Chat.defaultTitle)
        XCTAssertFalse(chat.hasAutoTitled, "a later message should be allowed to retry")
    }
}
