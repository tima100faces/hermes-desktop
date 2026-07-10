import SwiftUI

// MARK: - ProjectRow

struct ProjectRow: View {

    let project: Project

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 13))
                .foregroundStyle(Color.hkMuted)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.hkInk)
                    .lineLimit(1)
                Text(lastActiveText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hkNeutral)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.sm)
        .contentShape(Rectangle())
    }

    private var lastActiveText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: project.lastActiveAt, relativeTo: Date())
    }
}
