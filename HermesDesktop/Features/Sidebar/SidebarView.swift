import SwiftUI
import SwiftData

// MARK: - SidebarView
//
// Custom dark sidebar (docs/UI-SPEC.md §9). Rendered inside a plain
// HStack (not NavigationSplitView) so macOS system materials never
// override the hkPanel background.
//
// The project list is a ScrollView + buttons, NOT a List: the native
// macOS List draws its own full-width selection highlight on top of
// listRowBackground, which is impossible to disable cleanly. Do not
// convert this back to List.

struct SidebarView: View {

    let onSelectProject: (Project) -> Void

    @State private var viewModel = SidebarViewModel()

    @Query(sort: \Project.lastActiveAt, order: .reverse)
    private var projects: [Project]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Clearance for the floating traffic-light window controls
            // (the window uses .hiddenTitleBar).
            Color.clear.frame(height: 36)

            // Header
            HStack {
                Text("Projects")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.hkNeutral)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { viewModel.isCreatingProject = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hkNeutral)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("New project")
            }
            .padding(.horizontal, Space.md)
            .padding(.bottom, Space.sm)

            // Project list — custom selection, no system List highlight.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(projects) { project in
                        Button {
                            viewModel.selectedProject = project
                        } label: {
                            ProjectRow(
                                project: project,
                                isSelected: viewModel.selectedProject == project
                            )
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(viewModel.selectedProject == project
                                      ? Color.hkAccentDim
                                      : Color.clear)
                        )
                        .contextMenu {
                            contextMenuActions(for: project)
                        }
                    }
                }
                .padding(.horizontal, Space.sm)
            }
            .scrollIndicators(.hidden)

            // Agent status footer.
            // TODO: bind the dot color and label to the agent identity and
            // a real Hermes API health check (next stage — UI-SPEC.md §10).
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(Color.hkSuccess)
                    .frame(width: 7, height: 7)
                Text("Ржавчик")
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkNeutral)
                Spacer()
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + 2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
        }
        .background(Color.hkPanel)
        .sheet(isPresented: $viewModel.isCreatingProject) {
            CreateProjectSheet(viewModel: viewModel, modelContext: modelContext)
        }
        .alert("Delete Project?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) { viewModel.confirmDelete(context: modelContext) }
        } message: {
            Text("This will permanently delete the project and all its messages.")
        }
        .onChange(of: viewModel.selectedProject) { _, project in
            if let project { onSelectProject(project) }
        }
    }

    @ViewBuilder
    private func contextMenuActions(for project: Project) -> some View {
        Button("Delete", role: .destructive) {
            viewModel.requestDelete(project)
        }
    }
}

// MARK: - Preview

#Preview {
    SidebarView(onSelectProject: { _ in })
        .modelContainer(previewContainer)
        .frame(width: 220, height: 400)
}

@MainActor
private let previewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Project.self, configurations: config)
    let project = Project(name: "Sample Project", conversationKey: "sample-project")
    container.mainContext.insert(project)
    try? container.mainContext.save()
    return container
}()
