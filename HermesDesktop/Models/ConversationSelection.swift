import Foundation

// MARK: - ConversationSelection

/// The sidebar's active selection — either a `Topic` (Runs API) or a
/// `Chat` (Sessions API). `ContentView` and `SidebarView` share one
/// binding of this type instead of two separate optionals, so selecting
/// one kind always deselects the other (docs/UI-SPEC.md §9).
enum ConversationSelection: Equatable {
    case topic(Topic)
    case chat(Chat)
}
