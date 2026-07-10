import SwiftUI
import SwiftData

// MARK: - CreateProjectSheet

/// A small modal sheet for entering a new project name.
struct CreateProjectSheet: View {

    // MARK: Dependencies

    @Bindable var viewModel: SidebarViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        VStack(spacing: Space.md) {
            Text("New Project")
                .font(.hkTitleEm)
                .foregroundColor(.hkInk)

            TextField("Project name", text: $viewModel.newProjectName)
                .textFieldStyle(.plain)
                .font(.hkBody)
                .foregroundColor(.hkInk)
                .padding(Space.sm)
                .background(Color.hkSurface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.hkRule, lineWidth: 1)
                )
                .onSubmit {
                    createAndDismiss()
                }

            if let error = viewModel.errorMessage {
                HStack(spacing: Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.hkCaption)
                    Text(error)
                        .font(.hkCaption)
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: Space.sm) {
                Button("Cancel", role: .cancel) {
                    viewModel.newProjectName = ""
                    viewModel.clearError()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    createAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.hkAccent)
                .disabled(viewModel.newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 320)
        .background(Color.hkPaper2)
    }

    // MARK: - Actions

    private func createAndDismiss() {
        viewModel.createProject(context: modelContext)
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Project.self,
        configurations: config
    )
    let context = container.mainContext

    CreateProjectSheet(
        viewModel: SidebarViewModel(),
        modelContext: context
    )
}
