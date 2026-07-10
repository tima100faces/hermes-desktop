import SwiftUI

// MARK: - ChatRow
//
// Sidebar chat row — same anatomy as `TopicRow` (docs/UI-SPEC.md §9),
// via the shared `ConversationRowContent`.

struct ChatRow: View {
    let chat: Chat
    var isSelected: Bool = false

    var body: some View {
        ConversationRowContent(
            name: chat.title,
            lastActiveAt: chat.lastActiveAt,
            isSelected: isSelected
        )
    }
}
