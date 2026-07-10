import SwiftUI
import SwiftData

// MARK: - RenameChatSheet

/// A small modal sheet for editing an existing chat's title.
struct RenameChatSheet: View {

    // MARK: Dependencies

    @Bindable var viewModel: ChatSidebarViewModel
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        VStack(spacing: Space.md) {
            Text("Rename chat")
                .font(.hkTitleEm)
                .foregroundColor(.hkInk)

            TextField("Chat name", text: $viewModel.renameChatName)
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
                .disabled(viewModel.renameChatName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(width: 320)
        .background(Color.hkPanel)
    }

    // MARK: - Actions

    private func renameAndDismiss() {
        Task {
            await viewModel.confirmRename(context: modelContext)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}
