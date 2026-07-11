import SwiftUI

// MARK: - ConversationRowContent
//
// Shared visual content for a sidebar chat row — same anatomy in both the
// "Pinned" and "Chats" sections per docs/UI-SPEC.md §9, kept in one
// place so a visual tweak doesn't need to be made twice.

struct ConversationRowContent: View {
    let name: String
    let lastActiveAt: Date
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.hkBody.weight(.medium))
                    .foregroundStyle(isSelected ? Color.hkInk : Color.hkMuted)
                    .lineLimit(1)
                Text(lastActiveText)
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

    private var lastActiveText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastActiveAt, relativeTo: Date())
    }
}

// MARK: - ConversationMenuButton
//
// "…" trigger for a sidebar row, revealed on hover — opens a menu with
// Rename / Pin / Delete. Same 26×26 ghost style as `IconActionButton`,
// placed as a sibling of the row's selection button (not nested inside its
// label) so the menu remains clickable.
//
// `onRename`/`onTogglePin` are optional so the same component serves three
// row kinds without duplicating this menu: a regular chat row (all three
// actions), a project's chat row (Rename + Delete — project chats can't be
// pinned, see docs/UI-SPEC.md §9), and a project row (Delete only).

struct ConversationMenuButton: View {
    var isPinned: Bool = false
    var onRename: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    let onDelete: () -> Void
    var help: String = "Actions"

    @State private var isHovering = false

    var body: some View {
        Menu {
            if let onRename {
                Button("Rename") { onRename() }
            }
            if let onTogglePin {
                Button(isPinned ? "Unpin" : "Pin") { onTogglePin() }
            }
            Button("Delete", role: .destructive) { onDelete() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(Color.hkNeutral)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .background(isHovering ? Color.hkHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .help(help)
    }
}
