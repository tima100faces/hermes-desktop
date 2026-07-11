// MARK: - HermesDesktopApp
//
// The @main entry point — app assembly, DI, and scene management.

import SwiftUI
import SwiftData

// MARK: - HermesDesktopApp

/// The root application struct for Hermes Desktop.
///
/// ## Scenes
/// - **WindowGroup**: Shows `OnboardingView` when the user has no API
///   credentials, or `ContentView` (sidebar + chat) when configured.
///   The window uses `.hiddenTitleBar` so the dark UI extends edge to
///   edge; the sidebar reserves clearance for the traffic lights.
/// - **Settings**: A standard macOS Settings window.
///
/// ## SwiftData
/// A shared `ModelContainer` for `Chat` and `Message` is injected into
/// the view hierarchy via `.modelContainer(for: ...)`. Before it's
/// created, `ChatMigrationService` transfers any pre-unification `Topic`/
/// `Chat`/`Project` data (see `docs/UI-SPEC.md` migration note) into the
/// new schema.
@main
struct HermesDesktopApp: App {

    // MARK: State

    /// The global DI container — alive for the app's lifetime.
    @State private var appState = AppState()

    /// Shared SwiftData container for chats and messages.
    private let modelContainer: ModelContainer = {
        ChatMigrationService.migrateIfNeeded()
        return try! ModelContainer(for: Chat.self, Message.self, Project.self)
    }()

    // MARK: Body

    var body: some Scene {
        WindowGroup {
            content
                .modelContainer(modelContainer)
                .task { await appState.initialize() }
                .frame(minWidth: 860, idealWidth: 1024, minHeight: 560, idealHeight: 680)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1024, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(
                keychainManager: appState.keychainManager,
                gitSyncService: appState.gitSyncService
            )
            .modelContainer(modelContainer)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Content

    /// Switches between onboarding and the main split-view based on
    /// whether API credentials have been configured.
    @ViewBuilder
    private var content: some View {
        if appState.isConfigured {
            ContentView(appState: appState)
        } else {
            OnboardingView {
                Task { await appState.initialize() }
            }
        }
    }
}

// MARK: - ContentView

/// The main application layout — a custom HStack split (sidebar +
/// chat). A plain HStack is used instead of NavigationSplitView on
/// purpose: the system split view applies macOS sidebar materials
/// that override the design-system hkPanel background
/// (docs/UI-SPEC.md §8).
private struct ContentView: View {

    // MARK: State

    let appState: AppState

    /// What's shown in the main pane — a chat or a project page.
    @State private var selection: SidebarSelection?

    /// Whether the Cmd+K quick-switcher overlay is shown.
    @State private var isPaletteShown = false

    @Query(sort: \Chat.lastActiveAt, order: .reverse)
    private var chats: [Chat]

    @Query private var projects: [Project]

    /// Every project id seen so far — seeded once from `projects` on
    /// first appearance so pre-existing projects are never mistaken for
    /// "just created". `nil` before that seeding happens.
    @State private var knownProjectIDs: Set<PersistentIdentifier>?

    /// The id of the project that should auto-focus its name field —
    /// set by `onChange(of: selection)` the moment selection lands on a
    /// project id not in `knownProjectIDs`, cleared once `ProjectView`
    /// consumes it. This (not a flag threaded through `SidebarView`) is
    /// how "+" in the sidebar's Projects section gets its new project's
    /// name field focused without touching the sidebar at all.
    @State private var autoFocusProjectID: PersistentIdentifier?

    // MARK: Body

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Group {
                    if let sessionsAPI = appState.sessionsAPI {
                        SidebarView(
                            connectionMonitor: appState.connectionMonitor,
                            selection: $selection,
                            sessionsAPI: sessionsAPI
                        )
                    }
                }
                .frame(width: 220)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .ignoresSafeArea()

                Group {
                    switch selection {
                    case .chat(let chat):
                        chatDetail(for: chat)
                    case .project(let project):
                        if let sessionsAPI = appState.sessionsAPI {
                            ProjectView(
                                project: project,
                                sessionsAPI: sessionsAPI,
                                autoFocusName: autoFocusProjectID == project.persistentModelID,
                                onAutoFocusConsumed: { autoFocusProjectID = nil },
                                onOpenChat: { chat in selection = .chat(chat) }
                            )
                            .id(project.persistentModelID)
                        } else {
                            emptyDetail
                        }
                    case nil:
                        emptyDetail
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.hkPage)
            .ignoresSafeArea()

            if isPaletteShown {
                ChatPaletteView(
                    chats: chats,
                    onSelect: { chat in
                        selection = .chat(chat)
                        isPaletteShown = false
                    },
                    onDismiss: { isPaletteShown = false }
                )
            }
        }
        .background {
            // Hidden trigger — Cmd+K opens the palette from anywhere in
            // the window, regardless of what currently has focus.
            Button("") { isPaletteShown = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            guard knownProjectIDs == nil else { return }
            knownProjectIDs = Set(projects.map(\.persistentModelID))
        }
        .onChange(of: selection) { _, newValue in
            guard case .project(let project) = newValue else { return }
            let id = project.persistentModelID
            guard var known = knownProjectIDs, !known.contains(id) else { return }
            known.insert(id)
            knownProjectIDs = known
            autoFocusProjectID = id
        }
    }

    // MARK: Chat Detail

    /// Picks the transport (`RunsConversationService` for pinned chats,
    /// `SessionsConversationService` otherwise) and, for a project chat,
    /// wires the header breadcrumb back to its project's page.
    @ViewBuilder
    private func chatDetail(for chat: Chat) -> some View {
        switch (chat.conversationKey, appState.runsAPI, appState.sessionsAPI) {
        case (.some, let runsAPI?, _):
            ChatView(
                title: chat.title,
                conversationService: RunsConversationService(runsAPI: runsAPI, chat: chat)
            )
            .id(chat.persistentModelID)
        case (_, _, let sessionsAPI?) where chat.sessionId != nil:
            ChatView(
                title: chat.title,
                conversationService: SessionsConversationService(sessionsAPI: sessionsAPI, chat: chat),
                projectName: chat.project?.name,
                onOpenProject: chat.project.map { project in { selection = .project(project) } }
            )
            .id(chat.persistentModelID)
        default:
            emptyDetail
        }
    }

    // MARK: Empty Detail

    /// Placeholder shown when no conversation is selected (first launch —
    /// otherwise the sidebar auto-selects the most recently active one).
    @ViewBuilder
    private var emptyDetail: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.hkNeutral)

            Text(chats.isEmpty ? "Start your first chat" : "Select a chat")
                .font(.hkBody)
                .foregroundStyle(Color.hkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hkPage)
    }
}
