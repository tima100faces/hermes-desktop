import SwiftUI
import SwiftData

// MARK: - CreateTopicSheet

/// A small modal sheet for entering a new topic name.
struct CreateTopicSheet: View {

    // MARK: Dependencies

    @Bindable var viewModel: SidebarViewModel
    let modelContext: ModelContext
    @Binding var selectedTopic: Topic?

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        VStack(spacing: Space.md) {
            Text("Новая тема")
                .font(.hkTitleEm)
                .foregroundColor(.hkInk)

            TextField("Название темы", text: $viewModel.newTopicName)
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
                    viewModel.newTopicName = ""
                    viewModel.clearError()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    createAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.hkAccent)
                .disabled(viewModel.newTopicName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 320)
        .background(Color.hkPanel)
    }

    // MARK: - Actions

    private func createAndDismiss() {
        viewModel.createTopic(context: modelContext, selectedTopic: &selectedTopic)
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Topic.self,
        configurations: config
    )
    let context = container.mainContext

    CreateTopicSheet(
        viewModel: SidebarViewModel(),
        modelContext: context,
        selectedTopic: .constant(nil)
    )
}
