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
/// A shared `ModelContainer` for `Project` and `Message` is injected
/// into the view hierarchy via `.modelContainer(for: ...)`.
@main
struct HermesDesktopApp: App {

    // MARK: State

    /// The global DI container — alive for the app's lifetime.
    @State private var appState = AppState()

    /// Shared SwiftData container for projects and messages.
    private let modelContainer: ModelContainer = {
        try! ModelContainer(for: Project.self, Message.self)
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

    /// The project the user has selected in the sidebar.
    @State private var selectedProject: Project?

    /// Whether the Cmd+K quick-switcher overlay is shown.
    @State private var isPaletteShown = false

    @Query(sort: \Project.lastActiveAt, order: .reverse)
    private var projects: [Project]

    // MARK: Body

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    connectionMonitor: appState.connectionMonitor,
                    selectedProject: $selectedProject
                )
                .frame(width: 220)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .ignoresSafeArea()

                Group {
                    if let project = selectedProject, let runsAPI = appState.runsAPI {
                        ChatView(project: project, runsAPI: runsAPI)
                            .id(project.persistentModelID)
                    } else {
                        emptyDetail
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.hkPage)
            .ignoresSafeArea()

            if isPaletteShown {
                ProjectPaletteView(
                    projects: projects,
                    onSelect: { project in
                        selectedProject = project
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
    }

    // MARK: Empty Detail

    /// Placeholder shown when no project is selected (first launch with
    /// zero projects — otherwise the sidebar auto-selects the most
    /// recent one).
    @ViewBuilder
    private var emptyDetail: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Color.hkNeutral)

            Text("Select a project")
                .font(.hkBody)
                .foregroundStyle(Color.hkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hkPage)
    }
}
