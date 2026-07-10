import SwiftUI
import SwiftData

// MARK: - RenameProjectSheet

/// A small modal sheet for editing an existing project's name.
struct RenameProjectSheet: View {

    // MARK: Dependencies

    @Bindable var viewModel: SidebarViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        VStack(spacing: Space.md) {
            Text("Rename Project")
                .font(.hkTitleEm)
                .foregroundColor(.hkInk)

            TextField("Project name", text: $viewModel.renameProjectName)
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
                    renameAndDismiss()
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
                    viewModel.cancelRename()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    renameAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.hkAccent)
                .disabled(viewModel.renameProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 320)
        .background(Color.hkPanel)
    }

    // MARK: - Actions

    private func renameAndDismiss() {
        viewModel.confirmRename(context: modelContext)
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

    RenameProjectSheet(
        viewModel: SidebarViewModel(),
        modelContext: context
    )
}
