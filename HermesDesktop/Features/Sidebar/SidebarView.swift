import SwiftUI
import SwiftData

// MARK: - SidebarView
//
// Custom dark sidebar (docs/UI-SPEC.md §9). Rendered inside a plain
// HStack (not NavigationSplitView) so macOS system materials never
// override the hkPanel background.
//
// Two sections: "Закреплённые" (only shown when at least one chat is
// pinned) above "Чаты" (docs/UI-SPEC.md §9). Both lists are
// ScrollView + buttons, NOT List: the native macOS List draws its own
// full-width selection highlight on top of listRowBackground, which is
// impossible to disable cleanly. Do not convert this back to List.

struct SidebarView: View {

    /// Health monitor for the footer status dot. Optional so previews
    /// and the unconfigured state work without one.
    var connectionMonitor: ConnectionMonitor?

    /// The app's single source of truth for which chat is active — shared
    /// with ContentView so the sidebar highlight stays in sync regardless
    /// of how the selection changed (sidebar click, Cmd+K palette, etc).
    @Binding var selection: Chat?

    @State private var chatViewModel: ChatSidebarViewModel

    /// The chat currently under the pointer — reveals its "…" menu.
    @State private var hoveredChat: Chat?

    /// Agent display name — editable in Settings → General.
    @AppStorage("agent_name") private var agentName: String = "Ржавчик"

    @Query(sort: \Chat.lastActiveAt, order: .reverse)
    private var chats: [Chat]

    @Environment(\.modelContext) private var modelContext

    private var pinnedChats: [Chat] {
        chats.filter(\.isPinned)
    }

    private var regularChats: [Chat] {
        chats.filter { !$0.isPinned }
    }

    init(
        connectionMonitor: ConnectionMonitor?,
        selection: Binding<Chat?>,
        sessionsAPI: SessionsAPIProtocol
    ) {
        self.connectionMonitor = connectionMonitor
        self._selection = selection
        self._chatViewModel = State(initialValue: ChatSidebarViewModel(sessionsAPI: sessionsAPI))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clearance for the floating traffic-light window controls
            // (the window uses .hiddenTitleBar).
            Color.clear.frame(height: 36)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if !pinnedChats.isEmpty {
                        sectionHeader(title: "Закреплённые")
                        ForEach(pinnedChats) { chat in
                            chatRow(chat)
                        }
                    }

                    sectionHeader(
                        title: "Чаты",
                        help: "Новый чат",
                        action: { Task { await createChat() } }
                    )
                    .padding(.top, pinnedChats.isEmpty ? 0 : Space.sm)
                    ForEach(regularChats) { chat in
                        chatRow(chat)
                    }
                }
                .padding(.horizontal, Space.sm)
            }
            .scrollIndicators(.hidden)

            // Agent status footer: name from Settings, dot from health check.
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                Text(agentName.isEmpty ? "Hermes" : agentName)
                    .font(.hkCaption)
                    .foregroundStyle(Color.hkNeutral)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + 2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
            }
            .help(statusHelp)
        }
        .background(Color.hkPanel)
        .sheet(isPresented: $chatViewModel.isRenamingChat) {
            RenameChatSheet(viewModel: chatViewModel, modelContext: modelContext)
        }
        .alert("Удалить чат?", isPresented: $chatViewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { chatViewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await chatViewModel.confirmDelete(context: modelContext)
                    if let deleted, selection == deleted {
                        selection = nil
                    }
                }
            }
        } message: {
            Text("Чат будет удалён навсегда.")
        }
        .onAppear {
            // Auto-open the most recently active chat on launch, so the
            // app starts in a chat instead of the empty placeholder
            // (docs/UI-SPEC.md §9).
            guard selection == nil else { return }
            selection = chats.first
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, help: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.hkNeutral)
                .textCase(.uppercase)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hkNeutral)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(help ?? "")
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.sm)
    }

    // MARK: - Rows

    private func chatRow(_ chat: Chat) -> some View {
        HStack(spacing: 0) {
            Button {
                selection = chat
            } label: {
                ChatRow(chat: chat, isSelected: selection == chat)
            }
            .buttonStyle(.plain)

            // Sibling of the selection Button (not nested in its label) so
            // the menu stays clickable.
            if hoveredChat == chat {
                ConversationMenuButton(
                    isPinned: chat.isPinned,
                    onRename: { chatViewModel.requestRename(chat) },
                    onTogglePin: { chatViewModel.togglePin(chat, context: modelContext) },
                    onDelete: { chatViewModel.requestDelete(chat) },
                    help: "Действия с чатом"
                )
                .padding(.trailing, Space.xs)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == chat ? Color.hkAccentDim : Color.clear)
        )
        .onHover { hovering in
            hoveredChat = hovering ? chat : (hoveredChat == chat ? nil : hoveredChat)
        }
        .contextMenu {
            Button("Rename") { chatViewModel.requestRename(chat) }
            Button(chat.isPinned ? "Открепить" : "Закрепить") {
                chatViewModel.togglePin(chat, context: modelContext)
            }
            Button("Delete", role: .destructive) { chatViewModel.requestDelete(chat) }
        }
    }

    // MARK: - Actions

    private func createChat() async {
        if let chat = await chatViewModel.createChat(context: modelContext) {
            selection = chat
        }
    }

    // MARK: - Status

    private var statusDotColor: Color {
        switch connectionMonitor?.status {
        case .online:  return .hkSuccess
        case .offline: return .hkError
        default:       return .hkNeutral
        }
    }

    private var statusHelp: String {
        switch connectionMonitor?.status {
        case .online:  return "Hermes API: online"
        case .offline: return "Hermes API: offline"
        default:       return "Hermes API: checking…"
        }
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        connectionMonitor: nil,
        selection: .constant(nil),
        sessionsAPI: PreviewSessionsAPI()
    )
    .modelContainer(previewContainer)
    .frame(width: 220, height: 400)
}

@MainActor
private let previewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Chat.self, configurations: config)
    let chat = Chat(conversationKey: "sample-topic", title: "Sample Topic", isPinned: true)
    container.mainContext.insert(chat)
    try? container.mainContext.save()
    return container
}()

/// No-op `SessionsAPIProtocol` stub — previews never trigger chat CRUD.
private actor PreviewSessionsAPI: SessionsAPIProtocol {
    func createSession() async throws -> SessionInfo { SessionInfo(id: "preview", title: nil) }
    func getSession(id: String) async throws -> SessionInfo { SessionInfo(id: id, title: nil) }
    func renameSession(id: String, title: String) async throws -> SessionInfo { SessionInfo(id: id, title: title) }
    func deleteSession(id: String) async throws {}
    func getMessages(sessionId: String) async throws -> [SessionMessage] { [] }
    func streamChat(sessionId: String, input: String) async throws -> (stream: AsyncStream<RunEvent>, cancel: @Sendable () -> Void) {
        (AsyncStream { $0.finish() }, {})
    }
}
