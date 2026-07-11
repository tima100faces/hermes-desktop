import SwiftUI
import AppKit

// MARK: - ContentHeaderView
//
// The single content-pane header — used by a plain chat, a project's chat
// (folder breadcrumb → "/" → title), and a project's own page (chrome
// only, no title content — the project name lives in the page body
// instead). Fixed 52pt bar, hkPanel background, 1px hairline divider
// (docs/UI-SPEC.md §9 "Единый хедер").

struct ContentHeaderView: View {

    enum Kind {
        /// A chat outside any project — just its title.
        case chat(title: String)
        /// A chat inside a project — folder icon + project name (clickable,
        /// opens the project) → "/" → chat title.
        case projectChat(projectName: String, chatTitle: String, onOpenProject: () -> Void)
        /// A project's own page — no title content, chrome only.
        case empty
    }

    let kind: Kind

    /// Optional fixed-size accessory pinned to the trailing edge (the
    /// subagent-count badge on chat headers). Never shrinks — the title
    /// content truncates first to make room for it.
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 0) {
            content
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
        .background(Color.hkPanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .chat(let title):
            Text(title)
                .font(.hkBodyEm)
                .foregroundStyle(Color.hkInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)

        case .projectChat(let projectName, let chatTitle, let onOpenProject):
            HStack(spacing: 0) {
                ProjectBreadcrumbButton(projectName: projectName, action: onOpenProject)
                    .padding(.trailing, 8)

                Text("/")
                    .font(.hkBody)
                    .foregroundStyle(Color.hkNeutral)
                    .padding(.trailing, 8)

                // Truncates last — the breadcrumb gives up space first
                // (docs/UI-SPEC.md §9).
                Text(chatTitle)
                    .font(.hkBodyEm)
                    .foregroundStyle(Color.hkInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(chatTitle)
                    .layoutPriority(1)
            }

        case .empty:
            EmptyView()
        }
    }
}

// MARK: - ProjectBreadcrumbButton
//
// The folder icon + project name — one clickable zone, no background or
// underline, rust text/icon on hover with a pointing-hand cursor.

private struct ProjectBreadcrumbButton: View {
    let projectName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                // Truncates first, down to a 60pt floor, before the chat
                // title starts losing space (docs/UI-SPEC.md §9).
                Text(projectName)
                    .font(.hkBody.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 60, alignment: .leading)
            }
            .foregroundStyle(isHovering ? Color.hkAccent2 : Color.hkMuted)
        }
        .buttonStyle(.plain)
        .help(projectName)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
