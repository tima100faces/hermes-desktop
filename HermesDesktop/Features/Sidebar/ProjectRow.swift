import SwiftUI

// MARK: - ProjectRow

/// A single row in the sidebar project list.
///
/// Displays the project name and a relative "last active" timestamp.
struct ProjectRow: View {

    // MARK: Model

    let project: Project

    // MARK: Body

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(project.name)
                    .font(.hkBody)
                    .foregroundColor(.hkInk)
                    .lineLimit(1)

                Text(lastActiveText)
                    .font(.hkCaption)
                    .foregroundColor(.hkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.sm)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    /// Relative date string for `lastActiveAt`.
    private var lastActiveText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: project.lastActiveAt, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    let project = Project(name: "My Project", conversationKey: "my-project")

    List {
        ProjectRow(project: project)
            .listRowBackground(Color.hkPaper)
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 60)
    .background(Color.hkPaper)
}
