import Foundation
import SwiftData

// MARK: - SearchService

/// An actor that provides full-text search over `Message` objects in SwiftData.
///
/// Isolation is enforced via Swift 6 strict concurrency: all access to
/// `ModelContext` flows through the actor's `search(query:in:)` method.
public actor SearchService {

    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Search messages whose `content` contains `query` (case-insensitive).
    ///
    /// Results are sorted newest-first and capped at 50 items. An empty or
    /// whitespace-only query returns an empty array immediately.
    ///
    /// - Parameters:
    ///   - query: The search string.
    ///   - context: A SwiftData `ModelContext` to perform the fetch against.
    /// - Returns: Matching `Message` instances, newest first, or `[]` on error.
    public func search(query: String, in context: ModelContext) async -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let predicate = #Predicate<Message> { message in
                message.content.localizedStandardContains(trimmed)
            }

            var descriptor = FetchDescriptor<Message>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 50

            return try context.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Mock data

    /// Create `count` `Message` instances with Lorem Ipsum content for
    /// SwiftUI previews and performance testing.
    ///
    /// - Parameter count: Number of mock messages to generate.
    /// - Returns: An array of `Message` instances with randomised content.
    public static func mock(count: Int) -> [Message] {
        let loremWords = [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur",
            "adipiscing", "elit", "sed", "do", "eiusmod", "tempor",
            "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua",
            "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris",
            "nisi", "ut", "aliquip", "ex", "ea", "commodo", "consequat",
        ]

        let roles: [Message.Role] = [.user, .assistant, .tool]

        var messages: [Message] = []

        for i in 0 ..< count {
            // Build a short "sentence" from random words
            let wordCount = Int.random(in: 5 ... 20)
            let sentence = (0 ..< wordCount)
                .map { _ in loremWords.randomElement()! }
                .joined(separator: " ")
                .capitalized

            let role = roles.randomElement()!
            let message = Message(content: sentence + ".", role: role)

            // Stagger timestamps so sorting is observable
            message.timestamp = Date(timeIntervalSinceNow: -Double(i) * 60)

            messages.append(message)
        }

        return messages
    }
}
