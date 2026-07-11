import SwiftUI
import SwiftData

// MARK: - ProjectView
//
// A project's page — replaces the chat pane when a project is selected
// (docs/UI-SPEC.md §9). Editable name + instructions (autosaved as you
// type), and the project's own chat list. Reuses `ChatSidebarViewModel`
// for chat create/rename/delete — rename and delete behave exactly like a
// regular chat (same `RenameChatSheet`, same confirmation alert); only
// pinning is unavailable for project chats.

struct ProjectView: View {

    @Bindable var project: Project
    let sessionsAPI: SessionsAPIProtocol
    let onOpenChat: (Chat) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var chatViewModel: ChatSidebarViewModel
    @State private var hoveredChat: Chat?

    init(project: Project, sessionsAPI: SessionsAPIProtocol, onOpenChat: @escaping (Chat) -> Void) {
        self.project = project
        self.sessionsAPI = sessionsAPI
        self.onOpenChat = onOpenChat
        _chatViewModel = State(initialValue: ChatSidebarViewModel(sessionsAPI: sessionsAPI))
    }

    private var sortedChats: [Chat] {
        project.chats.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                nameField
                instructionsField
                chatsSection
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.hkPage)
        .sheet(isPresented: $chatViewModel.isRenamingChat) {
            RenameChatSheet(viewModel: chatViewModel, modelContext: modelContext)
        }
        .alert("Delete chat?", isPresented: $chatViewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { chatViewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task { await chatViewModel.confirmDelete(context: modelContext) }
            }
        } message: {
            Text("This chat will be permanently deleted.")
        }
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("Project name", text: $project.name, prompt: Text("Untitled project"))
            .textFieldStyle(.plain)
            .font(.hkHeading)
            .foregroundStyle(Color.hkInk)
            .onChange(of: project.name) { _, _ in try? modelContext.save() }
    }

    // MARK: - Instructions

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Instructions")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.hkNeutral)
                .textCase(.uppercase)

            TextEditor(text: $project.instructions)
                .font(.hkBody)
                .foregroundStyle(Color.hkInk)
                .scrollContentBackground(.hidden)
                .frame(height: 120)
                .padding(Space.sm)
                .background(Color.hkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.hkRule, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: project.instructions) { _, _ in try? modelContext.save() }

            Text("Sent with every message in this project. Keep it short.")
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
        }
    }

    // MARK: - Chats

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Chats")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.hkNeutral)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { Task { await createChat() } }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hkNeutral)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("New chat")
            }

            if sortedChats.isEmpty {
                Text("No chats yet")
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkNeutral)
                    .padding(.vertical, Space.xs)
            }

            ForEach(sortedChats) { chat in
                chatRow(chat)
            }
        }
    }

    private func chatRow(_ chat: Chat) -> some View {
        HStack(spacing: 0) {
            Button {
                onOpenChat(chat)
            } label: {
                ChatRow(chat: chat)
            }
            .buttonStyle(.plain)

            if hoveredChat == chat {
                ConversationMenuButton(
                    onRename: { chatViewModel.requestRename(chat) },
                    onDelete: { chatViewModel.requestDelete(chat) },
                    help: "Chat actions"
                )
                .padding(.trailing, Space.xs)
            }
        }
        .onHover { hovering in
            hoveredChat = hovering ? chat : (hoveredChat == chat ? nil : hoveredChat)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { chatViewModel.requestRename(chat) }
            Button("Delete", role: .destructive) { chatViewModel.requestDelete(chat) }
        }
    }

    // MARK: - Actions

    private func createChat() async {
        if let chat = await chatViewModel.createChat(context: modelContext, project: project) {
            onOpenChat(chat)
        }
    }
}
