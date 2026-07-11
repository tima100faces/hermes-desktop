import Foundation

// MARK: - SidebarSelection

/// What's currently shown in the main pane — a single source of truth
/// shared between `ContentView` and `SidebarView` via one `@Binding`, same
/// reasoning as the old single `Chat?` selection (docs/UI-SPEC.md §9): a
/// second, separately-tracked selection state is how a past bug (palette
/// picks not reflected in the sidebar highlight) happened.
enum SidebarSelection: Hashable {
    case chat(Chat)
    case project(Project)
}
