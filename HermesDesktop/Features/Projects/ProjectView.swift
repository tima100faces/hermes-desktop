import SwiftUI
import SwiftData

// MARK: - ProjectView
//
// A project's page — replaces the chat pane when a project is selected
// (docs/UI-SPEC.md §9). Shares `ContentHeaderView` with `ChatView` (empty
// variant — the project name lives in the page body, not the header).
// Editable name (commit on blur/Enter) and instructions (live, debounced
// autosave), and the project's own chat list. Reuses `ChatSidebarViewModel`
// for chat create/rename/delete — rename and delete behave exactly like a
// regular chat (same `RenameChatSheet`, same confirmation alert); only
// pinning is unavailable for project chats.

struct ProjectView: View {

    @Bindable var project: Project
    let sessionsAPI: SessionsAPIProtocol
    let onOpenChat: (Chat) -> Void

    /// `true` only for the page shown right after this project was
    /// created via the sidebar's "+" — focuses and fully selects the name
    /// field so typing replaces "New project" outright. `false` for every
    /// later visit to this project.
    let autoFocusName: Bool

    /// Called once, right after this view's first appearance, so the
    /// owner (`ContentView`) can clear its "just created" flag — without
    /// this, revisiting the same project later would auto-focus again.
    let onAutoFocusConsumed: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var chatViewModel: ChatSidebarViewModel
    @State private var hoveredChat: Chat?

    // MARK: Name Field State

    @FocusState private var isNameFocused: Bool
    @State private var nameDraft: String
    @State private var isHoveringName = false

    // MARK: Instructions Field State

    @State private var instructionsHeight: CGFloat = 96
    @State private var isInstructionsFocused = false
    @State private var saveInstructionsTask: Task<Void, Never>?

    // MARK: New Chat Button State

    @State private var isHoveringNewChat = false

    init(
        project: Project,
        sessionsAPI: SessionsAPIProtocol,
        autoFocusName: Bool = false,
        onAutoFocusConsumed: @escaping () -> Void = {},
        onOpenChat: @escaping (Chat) -> Void
    ) {
        self.project = project
        self.sessionsAPI = sessionsAPI
        self.autoFocusName = autoFocusName
        self.onAutoFocusConsumed = onAutoFocusConsumed
        self.onOpenChat = onOpenChat
        _chatViewModel = State(initialValue: ChatSidebarViewModel(sessionsAPI: sessionsAPI))
        _nameDraft = State(initialValue: project.name)
    }

    private var sortedChats: [Chat] {
        project.chats.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ContentHeaderView(kind: .empty)

                ScrollView {
                    columnContent
                        .frame(width: columnWidth(for: geometry.size.width), alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Space.xl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.hkPage)
        .onAppear {
            if autoFocusName {
                isNameFocused = true
            }
            onAutoFocusConsumed()
        }
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

    /// `min(680, paneWidth − 48)` — caps the column at 680pt, but never
    /// closer than 24pt to either edge of a narrower pane.
    private func columnWidth(for paneWidth: CGFloat) -> CGFloat {
        min(680, paneWidth - 48)
    }

    private var columnContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField
            Spacer().frame(height: Space.lg)
            instructionsSection
            Spacer().frame(height: Space.xl)
            chatsSection
        }
    }

    // MARK: - Name

    private var nameField: some View {
        let showBackground = isHoveringName || isNameFocused
        let showPencil = isHoveringName && !isNameFocused
        let horizontalPad: CGFloat = showBackground ? 8 : 0

        return HStack(spacing: 8) {
            TextField("New project", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.hkInk)
                .focused($isNameFocused)
                .onSubmit { isNameFocused = false }

            if showPencil {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hkNeutral)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, horizontalPad)
        .background(showBackground ? Color.hkSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        // Cancels the padding just added above so the field's leading edge
        // (and thus the text) never shifts — only the background grows
        // around it (docs/UI-SPEC.md §9).
        .padding(.horizontal, -horizontalPad)
        .contentShape(Rectangle())
        .onHover { isHoveringName = $0 }
        .onChange(of: isNameFocused) { wasFocused, isFocusedNow in
            guard wasFocused, !isFocusedNow else { return }
            commitNameEdit()
        }
    }

    private func commitNameEdit() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Empty name on blur reverts rather than saving.
            nameDraft = project.name
            return
        }
        project.name = trimmed
        nameDraft = trimmed
        try? modelContext.save()
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Instructions")
            Spacer().frame(height: Space.sm)
            instructionsEditor
            Spacer().frame(height: 6)
            Text("Sent with every message in this project — keep it short.")
                .font(.hkCaption)
                .foregroundStyle(Color.hkNeutral)
        }
    }

    private var instructionsEditor: some View {
        ZStack(alignment: .topLeading) {
            if project.instructions.isEmpty {
                Text("Add instructions for all chats in this project…")
                    .font(.hkBody)
                    .foregroundStyle(Color.hkNeutral)
                    .allowsHitTesting(false)
            }
            GrowingTextEditor(
                text: $project.instructions,
                height: $instructionsHeight,
                minHeight: 96,
                maxHeight: 240,
                autoFocus: false,
                onFocusChange: { focused in isInstructionsFocused = focused }
            )
        }
        .frame(height: instructionsHeight)
        .padding(12)
        .background(Color.hkSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isInstructionsFocused ? Color.hkAccentDim : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: project.instructions) { _, _ in
            scheduleInstructionsSave()
        }
    }

    private func scheduleInstructionsSave() {
        saveInstructionsTask?.cancel()
        saveInstructionsTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    // MARK: - Chats

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    sectionLabel("Chats")
                    Text("\(sortedChats.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.hkNeutral)
                }
                Spacer(minLength: 0)
                newChatButton
            }

            if sortedChats.isEmpty {
                Text("No chats yet. Start one to work in this project.")
                    .font(.hkBody)
                    .foregroundStyle(Color.hkNeutral)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Space.lg)
            } else {
                Spacer().frame(height: Space.sm)
                VStack(spacing: 2) {
                    ForEach(sortedChats) { chat in
                        chatRow(chat)
                    }
                }
            }
        }
    }

    private var newChatButton: some View {
        Button(action: { Task { await createChat() } }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                Text("New chat")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.hkAccent2)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHoveringNewChat ? Color.hkSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHoveringNewChat = $0 }
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

    // MARK: - Shared Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.hkNeutral)
            .textCase(.uppercase)
    }

    // MARK: - Actions

    private func createChat() async {
        if let chat = await chatViewModel.createChat(context: modelContext, project: project) {
            onOpenChat(chat)
        }
    }
}
