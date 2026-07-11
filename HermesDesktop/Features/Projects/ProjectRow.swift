import SwiftUI

// MARK: - ProjectRow
//
// Sidebar project row — same anatomy as `ConversationRowContent` (name +
// secondary caption line, selection bar) but with a leading folder glyph
// and a chat count instead of a relative timestamp, so it doesn't read as
// just another chat (docs/UI-SPEC.md §9).

struct ProjectRow: View {
    let project: Project
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.hkAccent2 : Color.hkNeutral)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.hkBody.weight(.medium))
                    .foregroundStyle(isSelected ? Color.hkInk : Color.hkMuted)
                    .lineLimit(1)
                Text(chatCountText)
                    .font(.hkCaption)
                    .foregroundStyle(isSelected ? Color.hkAccent2 : Color.hkNeutral)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm - 2)
        .padding(.horizontal, Space.sm + 2)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.hkAccent)
                    .frame(width: 2)
                    .padding(.vertical, Space.xs)
            }
        }
        .contentShape(Rectangle())
    }

    private var chatCountText: String {
        let count = project.chats.count
        return count == 1 ? "1 chat" : "\(count) chats"
    }
}
