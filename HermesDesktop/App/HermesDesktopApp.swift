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
/// - **Settings**: A standard macOS Settings window with connection
///   configuration, git sync, and about info.
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
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(
                keychainManager: appState.keychainManager,
                gitSyncService: appState.gitSyncService
            )
            .modelContainer(modelContainer)
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

/// The main application split view — sidebar projects on the left,
/// selected project's chat on the right.
private struct ContentView: View {

    // MARK: State

    let appState: AppState

    /// The project the user has selected in the sidebar.
    @State private var selectedProject: Project?

    // MARK: Body

    var body: some View {
        NavigationSplitView {
            SidebarView(onSelectProject: { project in
                selectedProject = project
            })
        } detail: {
            if let project = selectedProject, let runsAPI = appState.runsAPI {
                ChatView(project: project, runsAPI: runsAPI)
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Empty Detail

    /// Placeholder shown when no project is selected.
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
        .background(Color.hkPaper)
    }
}
