import SwiftUI
import SwiftData

// MARK: - SidebarView
//
// Custom dark sidebar (docs/UI-SPEC.md §9). Rendered inside a plain
// HStack (not NavigationSplitView) so macOS system materials never
// override the hkPanel background.
//
// The topic list is a ScrollView + buttons, NOT a List: the native
// macOS List draws its own full-width selection highlight on top of
// listRowBackground, which is impossible to disable cleanly. Do not
// convert this back to List.

struct SidebarView: View {

    /// Health monitor for the footer status dot. Optional so previews
    /// and the unconfigured state work without one.
    var connectionMonitor: ConnectionMonitor?

    /// The app's single source of truth for which topic is active —
    /// shared with ContentView so the sidebar highlight stays in sync
    /// regardless of how the topic changed (sidebar click, Cmd+K
    /// palette, etc).
    @Binding var selectedTopic: Topic?

    @State private var viewModel = SidebarViewModel()

    /// The topic currently under the pointer — reveals its "…" menu.
    @State private var hoveredTopic: Topic?

    /// Agent display name — editable in Settings → General.
    @AppStorage("agent_name") private var agentName: String = "Ржавчик"

    @Query(sort: \Topic.lastActiveAt, order: .reverse)
    private var topics: [Topic]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Clearance for the floating traffic-light window controls
            // (the window uses .hiddenTitleBar).
            Color.clear.frame(height: 36)

            // Header
            HStack {
                Text("Темы")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.hkNeutral)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { viewModel.isCreatingTopic = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.hkNeutral)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Новая тема")
            }
            .padding(.horizontal, Space.md)
            .padding(.bottom, Space.sm)

            // Topic list — custom selection, no system List highlight.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(topics) { topic in
                        HStack(spacing: 0) {
                            Button {
                                selectedTopic = topic
                            } label: {
                                TopicRow(
                                    topic: topic,
                                    isSelected: selectedTopic == topic
                                )
                            }
                            .buttonStyle(.plain)

                            // Sibling of the selection Button (not nested in
                            // its label) so the menu stays clickable.
                            if hoveredTopic == topic {
                                TopicMenuButton(
                                    onRename: { viewModel.requestRename(topic) },
                                    onDelete: { viewModel.requestDelete(topic) }
                                )
                                .padding(.trailing, Space.xs)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTopic == topic
                                      ? Color.hkAccentDim
                                      : Color.clear)
                        )
                        .onHover { hovering in
                            hoveredTopic = hovering ? topic : (hoveredTopic == topic ? nil : hoveredTopic)
                        }
                        .contextMenu {
                            contextMenuActions(for: topic)
                        }
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
            CreateTopicSheet(viewModel: viewModel, modelContext: modelContext, selectedTopic: $selectedTopic)
        }
        .sheet(isPresented: $viewModel.isRenamingTopic) {
            RenameTopicSheet(viewModel: viewModel, modelContext: modelContext)
        }
        .alert("Удалить тему?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete(context: modelContext, selectedTopic: &selectedTopic)
            }
        } message: {
            Text("Тема и вся переписка будут удалены навсегда.")
        }
        .onAppear {
            // Auto-open the most recent topic on launch, so the app
            // starts in a chat instead of the empty placeholder
            // (docs/UI-SPEC.md §9).
            if selectedTopic == nil, let mostRecent = topics.first {
                selectedTopic = mostRecent
            }
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

    @ViewBuilder
    private func contextMenuActions(for topic: Topic) -> some View {
        Button("Rename") {
            viewModel.requestRename(topic)
        }
        Button("Delete", role: .destructive) {
            viewModel.requestDelete(topic)
        }
    }
}

// MARK: - Preview

#Preview {
    SidebarView(selectedTopic: .constant(nil))
        .modelContainer(previewContainer)
        .frame(width: 220, height: 400)
}

@MainActor
private let previewContainer: ModelContainer = {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Topic.self, configurations: config)
    let topic = Topic(name: "Sample Topic", conversationKey: "sample-topic")
    container.mainContext.insert(topic)
    try? container.mainContext.save()
    return container
}()
