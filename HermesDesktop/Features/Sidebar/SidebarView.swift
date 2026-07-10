import SwiftUI
import SwiftData

// MARK: - SidebarView

struct SidebarView: View {

    let onSelectProject: (Project) -> Void

    @State private var viewModel = SidebarViewModel()

    @Query(sort: \Project.lastActiveAt, order: .reverse)
    private var projects: [Project]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hkNeutral)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { viewModel.isCreatingProject = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hkMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.md)
            .padding(.bottom, Space.sm)

            Divider()
                .overlay(Color.hkBorder)

            // Project list
            List(selection: $viewModel.selectedProject) {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                        .tag(project)
                        .listRowBackground(
                            viewModel.selectedProject == project
                                ? Color.hkAccentDim
                                : Color.clear
                        )
                        .contextMenu {
                            contextMenuActions(for: project)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 220)
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
        .frame(width: 240, height: 400)
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
