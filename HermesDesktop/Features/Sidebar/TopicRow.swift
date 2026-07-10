import SwiftUI

// MARK: - TopicRow
//
// Sidebar topic row. Selected state: rust bar on the leading edge +
// light-rust timestamp (background fill is applied by SidebarView).

struct TopicRow: View {
    let topic: Topic
    var isSelected: Bool = false

    var body: some View {
        ConversationRowContent(
            name: topic.name,
            lastActiveAt: topic.lastActiveAt,
            isSelected: isSelected
        )
    }
}

