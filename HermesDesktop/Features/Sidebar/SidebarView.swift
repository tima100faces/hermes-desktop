import SwiftUI
import SwiftData

// MARK: - SidebarView
//
// Custom dark sidebar (docs/UI-SPEC.md §9). Rendered inside a plain
// HStack (not NavigationSplitView) so macOS system materials never
// override the hkPanel background.
//
// Two sections, Чаты above Темы (docs/task-topics-and-chats.md §Этап 2).
// Both lists are ScrollView + buttons, NOT List: the native macOS List
// draws its own full-width selection highlight on top of
// listRowBackground, which is impossible to disable cleanly. Do not
// convert this back to List.

struct SidebarView: View {

    /// Health monitor for the footer status dot. Optional so previews
    /// and the unconfigured state work without one.
    var connectionMonitor: ConnectionMonitor?

    /// The app's single source of truth for which conversation is active —
    /// shared with ContentView so the sidebar highlight stays in sync
    /// regardless of how the selection changed (sidebar click, Cmd+K
    /// palette, etc).
    @Binding var selection: ConversationSelection?

    @State private var viewModel = SidebarViewModel()
    @State private var chatViewModel: ChatSidebarViewModel

    /// The topic currently under the pointer — reveals its "…" menu.
    @State private var hoveredTopic: Topic?

    /// The chat currently under the pointer — reveals its "…" menu.
    @State private var hoveredChat: Chat?

    /// Agent display name — editable in Settings → General.
    @AppStorage("agent_name") private var agentName: String = "Ржавчик"

    @Query(sort: \Chat.lastActiveAt, order: .reverse)
    private var chats: [Chat]

    @Query(sort: \Topic.lastActiveAt, order: .reverse)
    private var topics: [Topic]

    @Environment(\.modelContext) private var modelContext

    init(
        connectionMonitor: ConnectionMonitor?,
        selection: Binding<ConversationSelection?>,
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
                    sectionHeader(
                        title: "Чаты",
                        help: "Новый чат",
                        action: { Task { await createChat() } }
                    )
                    ForEach(chats) { chat in
                        chatRow(chat)
                    }

                    sectionHeader(
                        title: "Темы",
                        help: "Новая тема",
                        action: { viewModel.isCreatingTopic = true }
                    )
                    .padding(.top, Space.sm)
                    ForEach(topics) { topic in
                        topicRow(topic)
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
        .sheet(isPresented: $viewModel.isCreatingTopic) {
            CreateTopicSheet(viewModel: viewModel, modelContext: modelContext, selection: $selection)
        }
        .sheet(isPresented: $viewModel.isRenamingTopic) {
            RenameTopicSheet(viewModel: viewModel, modelContext: modelContext)
        }
        .sheet(isPresented: $chatViewModel.isRenamingChat) {
            RenameChatSheet(viewModel: chatViewModel, modelContext: modelContext)
        }
        .alert("Удалить тему?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(context: modelContext, selection: &selection)
            }
        } message: {
            Text("Тема и вся переписка будут удалены навсегда.")
        }
        .alert("Удалить чат?", isPresented: $chatViewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { chatViewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await chatViewModel.confirmDelete(context: modelContext)
                    if case .chat(let selected) = selection, selected == deleted {
                        selection = nil
                    }
                }
            }
        } message: {
            Text("Чат будет удалён навсегда.")
        }
        .onAppear {
            // Auto-open the most recently active conversation on launch, so
            // the app starts in a chat instead of the empty placeholder
            // (docs/UI-SPEC.md §9) — whichever of the two lists is freshest.
            guard selection == nil else { return }
            switch (chats.first, topics.first) {
            case (let chat?, let topic?):
                selection = chat.lastActiveAt > topic.lastActiveAt ? .chat(chat) : .topic(topic)
            case (let chat?, nil):
                selection = .chat(chat)
            case (nil, let topic?):
                selection = .topic(topic)
            case (nil, nil):
                break
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, help: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.hkNeutral)
                .textCase(.uppercase)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.hkNeutral)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(help)
        }
        .padding(.horizontal, Space.sm)
        .padding(.bottom, Space.sm)
    }

    // MARK: - Rows

    private func topicRow(_ topic: Topic) -> some View {
        HStack(spacing: 0) {
            Button {
                selection = .topic(topic)
            } label: {
                TopicRow(topic: topic, isSelected: selection == .topic(topic))
            }
            .buttonStyle(.plain)

            // Sibling of the selection Button (not nested in its label) so
            // the menu stays clickable.
            if hoveredTopic == topic {
                ConversationMenuButton(
                    onRename: { viewModel.requestRename(topic) },
                    onDelete: { viewModel.requestDelete(topic) },
                    help: "Действия с темой"
                )
                .padding(.trailing, Space.xs)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == .topic(topic) ? Color.hkAccentDim : Color.clear)
        )
        .onHover { hovering in
            hoveredTopic = hovering ? topic : (hoveredTopic == topic ? nil : hoveredTopic)
        }
        .contextMenu {
            Button("Rename") { viewModel.requestRename(topic) }
            Button("Delete", role: .destructive) { viewModel.requestDelete(topic) }
        }
    }

    private func chatRow(_ chat: Chat) -> some View {
        HStack(spacing: 0) {
            Button {
                selection = .chat(chat)
            } label: {
                ChatRow(chat: chat, isSelected: selection == .chat(chat))
            }
            .buttonStyle(.plain)

            if hoveredChat == chat {
                ConversationMenuButton(
                    onRename: { chatViewModel.requestRename(chat) },
                    onDelete: { chatViewModel.requestDelete(chat) },
                    help: "Действия с чатом"
                )
                .padding(.trailing, Space.xs)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == .chat(chat) ? Color.hkAccentDim : Color.clear)
        )
        .onHover { hovering in
            hoveredChat = hovering ? chat : (hoveredChat == chat ? nil : hoveredChat)
        }
        .contextMenu {
            Button("Rename") { chatViewModel.requestRename(chat) }
            Button("Delete", role: .destructive) { chatViewModel.requestDelete(chat) }
        }
    }

    // MARK: - Actions

    private func createChat() async {
        if let chat = await chatViewModel.createChat(context: modelContext) {
            selection = .chat(chat)
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
    let container = try! ModelContainer(for: Topic.self, Chat.self, configurations: config)
    let topic = Topic(name: "Sample Topic", conversationKey: "sample-topic")
    container.mainContext.insert(topic)
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
