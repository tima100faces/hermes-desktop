import Foundation
import SwiftData
import OSLog

private extension Logger {
    static let migration = Logger(subsystem: "com.hermes-desktop", category: "migration")
}

// MARK: - ChatMigrationService

/// One-time transfer of pre-unification data into the current unified
/// `Chat`/`Message` schema.
///
/// Two on-disk shapes are possible depending on how old the local store is,
/// distinguished by `didMigrateProjectsKey` (set by a previous release):
/// - Already past the Project→Topic rename: the store holds `Topic` +
///   `Chat` + `Message` under `PreUnificationSchema`. Every `Topic` becomes
///   a pinned, Runs API-backed `Chat`; every old `Chat` becomes an
///   unpinned, Sessions API-backed `Chat`.
/// - Never migrated at all (very old install): the store still holds the
///   original pre-rename `Project` + `Message` under `LegacyTopicSchema`.
///   Each `Project` becomes a pinned, Runs API-backed `Chat` directly —
///   skipping the intermediate `Topic` shape entirely.
///
/// Neither entity rename nor this merge is lightweight-inferrable for
/// SwiftData — from the store's perspective these are unrelated entities
/// appearing/disappearing, so a straight schema swap would silently orphan
/// existing data. Instead this reads the old store under its original
/// schema, moves that file aside, and writes matching `Chat`/`Message` rows
/// into a fresh store — before the app's own `Chat`/`Message` container
/// ever opens the default store URL.
///
/// Guarded by `didMigrateUnificationKey` in `UserDefaults` so it runs at
/// most once.
enum ChatMigrationService {

    private static let didMigrateProjectsKey = "did_migrate_projects_to_topics_v1"
    private static let didMigrateUnificationKey = "did_migrate_to_unified_chat_v1"

    /// Performs the migration if it hasn't run yet and a legacy store exists.
    ///
    /// Must be called before the app's main `Chat`/`Message` `ModelContainer`
    /// is created — it works directly against the default store file that
    /// container would otherwise open.
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didMigrateUnificationKey) else { return }

        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            // Fresh install — nothing to migrate.
            UserDefaults.standard.set(true, forKey: didMigrateProjectsKey)
            UserDefaults.standard.set(true, forKey: didMigrateUnificationKey)
            return
        }

        do {
            if UserDefaults.standard.bool(forKey: didMigrateProjectsKey) {
                try migrateFromTopicAndChat(storeURL: storeURL)
            } else {
                try migrateFromProject(storeURL: storeURL)
                UserDefaults.standard.set(true, forKey: didMigrateProjectsKey)
            }
            UserDefaults.standard.set(true, forKey: didMigrateUnificationKey)
        } catch {
            // Leave the flag unset so we retry next launch, and leave the
            // legacy store untouched — better to retry than lose data.
            Logger.migration.error("Chat unification migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - From Topic + Chat (current pre-unification shape)

    private static func migrateFromTopicAndChat(storeURL: URL) throws {
        let legacyConfig = ModelConfiguration(
            schema: Schema([
                PreUnificationSchema.Topic.self,
                PreUnificationSchema.Chat.self,
                PreUnificationSchema.Message.self,
            ]),
            url: storeURL
        )
        let legacyContainer = try ModelContainer(
            for: PreUnificationSchema.Topic.self, PreUnificationSchema.Chat.self, PreUnificationSchema.Message.self,
            configurations: legacyConfig
        )
        let legacyContext = ModelContext(legacyContainer)

        let legacyTopics = try legacyContext.fetch(FetchDescriptor<PreUnificationSchema.Topic>())
        let legacyChats = try legacyContext.fetch(FetchDescriptor<PreUnificationSchema.Chat>())
        guard !legacyTopics.isEmpty || !legacyChats.isEmpty else {
            Logger.migration.info("No legacy topics or chats found — nothing to migrate.")
            return
        }

        // Fully materialize everything into plain value types *before*
        // touching the store file below — SwiftData model objects lazily
        // fault their properties/relationships in from the backing store,
        // and reading them after `relocateLegacyStore` moves that file out
        // from under `legacyContext` crashes (fault fulfillment fails).
        var migrated: [MigratedChatData] = legacyTopics.map { topic in
            MigratedChatData(
                sessionId: nil,
                conversationKey: topic.conversationKey,
                title: topic.name,
                createdAt: topic.createdAt,
                lastActiveAt: topic.lastActiveAt,
                hasAutoTitled: true,
                isPinned: true,
                messages: topic.messages.map(LegacyMessageData.init)
            )
        }
        migrated += legacyChats.map { chat in
            MigratedChatData(
                sessionId: chat.sessionId,
                conversationKey: nil,
                title: chat.title,
                createdAt: chat.createdAt,
                lastActiveAt: chat.lastActiveAt,
                hasAutoTitled: chat.hasAutoTitled,
                isPinned: false,
                messages: chat.messages.map(LegacyMessageData.init)
            )
        }

        try relocateLegacyStore(at: storeURL)
        try write(migrated)
        Logger.migration.info("Migrated \(legacyTopics.count) topic(s) and \(legacyChats.count) chat(s) to unified chats.")
    }

    // MARK: - From Project (pre-rename shape, very old installs)

    private static func migrateFromProject(storeURL: URL) throws {
        let legacyConfig = ModelConfiguration(
            schema: Schema([LegacyTopicSchema.Project.self, LegacyTopicSchema.Message.self]),
            url: storeURL
        )
        let legacyContainer = try ModelContainer(
            for: LegacyTopicSchema.Project.self, LegacyTopicSchema.Message.self,
            configurations: legacyConfig
        )
        let legacyContext = ModelContext(legacyContainer)

        let legacyProjects = try legacyContext.fetch(FetchDescriptor<LegacyTopicSchema.Project>())
        guard !legacyProjects.isEmpty else {
            Logger.migration.info("No legacy projects found — nothing to migrate.")
            return
        }

        let migrated: [MigratedChatData] = legacyProjects.map { project in
            MigratedChatData(
                sessionId: nil,
                conversationKey: project.conversationKey,
                title: project.name,
                createdAt: project.createdAt,
                lastActiveAt: project.lastActiveAt,
                hasAutoTitled: true,
                isPinned: true,
                messages: project.messages.map(LegacyMessageData.init)
            )
        }

        try relocateLegacyStore(at: storeURL)
        try write(migrated)
        Logger.migration.info("Migrated \(legacyProjects.count) project(s) to unified chats.")
    }

    // MARK: - Shared Write Path

    /// Writes materialized chat data into a fresh unified `Chat`/`Message`
    /// store. Must run after `relocateLegacyStore` has cleared the default
    /// store URL.
    private static func write(_ chats: [MigratedChatData]) throws {
        let newContainer = try ModelContainer(for: Chat.self, Message.self)
        let newContext = ModelContext(newContainer)

        for data in chats {
            let chat: Chat
            if let sessionId = data.sessionId {
                chat = Chat(sessionId: sessionId, title: data.title)
            } else {
                chat = Chat(conversationKey: data.conversationKey!, title: data.title, isPinned: data.isPinned)
            }
            chat.createdAt = data.createdAt
            chat.lastActiveAt = data.lastActiveAt
            chat.hasAutoTitled = data.hasAutoTitled
            chat.isPinned = data.isPinned
            newContext.insert(chat)

            for messageData in data.messages {
                let message = Message(
                    content: messageData.content,
                    role: Message.Role(rawValue: messageData.role) ?? .assistant,
                    runId: messageData.runId
                )
                message.timestamp = messageData.timestamp
                message.chat = chat
                newContext.insert(message)
            }
        }

        try newContext.save()
    }

    /// Renames the old store files (`.store`, `-wal`, `-shm`) with a
    /// `.legacy-backup` suffix so the new container can claim the default
    /// store URL with a clean slate. Idempotent across the two migration
    /// paths above — only one of them runs per launch, but a leftover
    /// backup from a previous run is replaced rather than left to collide.
    private static func relocateLegacyStore(at storeURL: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: source.path + ".legacy-backup")
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: source, to: destination)
        }
    }
}

// MARK: - Plain Value Snapshots

/// Plain-value copy of a legacy message, safe to hold onto after the
/// backing store file has been moved.
private struct LegacyMessageData {
    let content: String
    let role: String
    let timestamp: Date
    let runId: String?

    init(content: String, role: String, timestamp: Date, runId: String?) {
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.runId = runId
    }

    init(_ message: PreUnificationSchema.Message) {
        self.init(content: message.content, role: message.role, timestamp: message.timestamp, runId: message.runId)
    }

    init(_ message: LegacyTopicSchema.Message) {
        self.init(content: message.content, role: message.role, timestamp: message.timestamp, runId: message.runId)
    }
}

/// Plain-value copy of a legacy `Topic`, `Chat`, or `Project` — whichever
/// pre-unification shape it came from — ready to write as a unified `Chat`.
private struct MigratedChatData {
    let sessionId: String?
    let conversationKey: String?
    let title: String
    let createdAt: Date
    let lastActiveAt: Date
    let hasAutoTitled: Bool
    let isPinned: Bool
    let messages: [LegacyMessageData]
}
