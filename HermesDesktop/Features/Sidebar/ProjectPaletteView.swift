import SwiftUI

// MARK: - ProjectPaletteView
//
// Cmd+K quick-switcher overlay (docs/UI-SPEC.md §10 item 2). Centered
// card over a 40%-black scrim: search field + filtered project list,
// arrow keys to move selection, Enter to open, Esc to dismiss.

struct ProjectPaletteView: View {
    let projects: [Project]
    let onSelect: (Project) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filtered: [Project] {
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search projects…", text: $query)
                .textFieldStyle(.plain)
                .font(.hkBody)
                .foregroundColor(.hkInk)
                .padding(Space.md)
                .focused($isSearchFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.return) {
                    confirmSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            list
        }
        .background(Color.hkSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.hkGlowStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 480)
        .onAppear { isSearchFocused = true }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            Text("No projects found")
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
                .padding(Space.md)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, project in
                        row(project: project, isSelected: index == selectedIndex)
                            .onTapGesture { onSelect(project) }
                    }
                }
                .padding(Space.sm)
            }
            .frame(maxHeight: 320)
        }
    }

    private func row(project: Project, isSelected: Bool) -> some View {
        Text(project.name)
            .font(.hkBody.weight(.medium))
            .foregroundStyle(isSelected ? Color.hkInk : Color.hkMuted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.sm + 2)
            .padding(.vertical, Space.sm - 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.hkAccentDim : Color.clear)
            )
            .contentShape(Rectangle())
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
    }

    private func confirmSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        onSelect(filtered[selectedIndex])
    }
}
