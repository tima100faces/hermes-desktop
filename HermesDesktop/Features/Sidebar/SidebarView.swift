import SwiftUI
import SwiftData

// MARK: - SidebarView

/// The primary sidebar of Hermes Desktop.
///
/// Displays a list of `Project` objects sorted by most-recently-active,
/// with create / delete capabilities and a selection callback.
struct SidebarView: View {

    // MARK: Dependencies

    /// Callback invoked whenever the selection changes.
    let onSelectProject: (Project) -> Void

    // MARK: State

    @State private var viewModel = SidebarViewModel()

    /// Sorted project list — most recently active first.
    @Query(
        sort: \Project.lastActiveAt,
        order: .reverse
    )
    private var projects: [Project]

    @Environment(\.modelContext) private var modelContext

    // MARK: Body

    var body: some View {
        List(selection: $viewModel.selectedProject) {
            Section("Projects") {
                if projects.isEmpty {
                    emptyState
                } else {
                    ForEach(projects) { project in
                        ProjectRow(project: project)
                            .tag(project)
                            .listRowBackground(
                                viewModel.selectedProject == project
                                    ? Color.hkAccent.opacity(0.15)
                                    : Color.clear
                            )
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    viewModel.requestDelete(project)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.hkPaper)
        .navigationTitle("Hermes")
        .toolbarBackground(Color.hkPaper, for: .windowToolbar)
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.isCreatingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isCreatingProject) {
            CreateProjectSheet(
                viewModel: viewModel,
                modelContext: modelContext
            )
        }
        .alert(
            "Delete Project?",
            isPresented: $viewModel.showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(context: modelContext)
            }
        } message: {
            Text("This will permanently delete the project and all its messages. This action cannot be undone.")
        }
        .onChange(of: viewModel.selectedProject) { _, project in
            if let project {
                onSelectProject(project)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.hkTitle)
                .foregroundColor(.hkNeutral)

            Text("No projects yet")
                .font(.hkBody)
                .foregroundColor(.hkNeutral)

            Text("Tap + to create your first project")
                .font(.hkCaption)
                .foregroundColor(.hkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Project.self,
        configurations: config
    )

    // Seed one project
    let context = container.mainContext
    let project = Project(name: "Sample Project", conversationKey: "sample-project")
    context.insert(project)
    try? context.save()

    return SidebarView(onSelectProject: { _ in })
        .modelContainer(container)
        .frame(width: 240, height: 400)
}
