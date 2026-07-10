import Foundation
import SwiftData
import OSLog

private extension Logger {
    static let migration = Logger(subsystem: "com.hermes-desktop", category: "migration")
}

// MARK: - TopicMigrationService

/// One-time transfer of pre-rename `Project`/`Message` data into the
/// current `Topic`/`Message` schema.
///
/// Renaming the `@Model` type from `Project` to `Topic` is not a
/// lightweight-inferrable change for SwiftData — from the store's
/// perspective the "Project" entity disappeared and an unrelated "Topic"
/// entity appeared, so a straight rename would silently orphan any
/// existing data. Instead this reads the old store under its original
/// schema (`LegacyTopicSchema`), moves that file aside, and writes
/// matching `Topic`/`Message` rows into a fresh store — before the app's
/// own `Topic`/`Message` container ever opens the default store URL.
///
/// Guarded by `didMigrateKey` in `UserDefaults` so it runs at most once.
enum TopicMigrationService {

    private static let didMigrateKey = "did_migrate_projects_to_topics_v1"

    /// Performs the migration if it hasn't run yet and a legacy store exists.
    ///
    /// Must be called before the app's main `Topic`/`Message` `ModelContainer`
    /// is created — it works directly against the default store file that
    /// container would otherwise open.
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didMigrateKey) else { return }

        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            // Fresh install — nothing to migrate.
            UserDefaults.standard.set(true, forKey: didMigrateKey)
            return
        }

        do {
            try migrate(storeURL: storeURL)
            UserDefaults.standard.set(true, forKey: didMigrateKey)
        } catch {
            // Leave the flag unset so we retry next launch, and leave the
            // legacy store untouched — better to retry than lose data.
            Logger.migration.error("Project → Topic migration failed: \(error.localizedDescription)")
        }
    }

    private static func migrate(storeURL: URL) throws {
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

        // Fully materialize every project and message into plain value types
        // *before* touching the store file below. SwiftData model objects
        // lazily fault their properties/relationships in from the backing
        // store; reading them after `relocateLegacyStore` moves that file
        // out from under `legacyContext` crashes (fault fulfillment fails).
        let projectsData: [LegacyProjectData] = legacyProjects.map { project in
            LegacyProjectData(
                name: project.name,
                conversationKey: project.conversationKey,
                createdAt: project.createdAt,
                lastActiveAt: project.lastActiveAt,
                messages: project.messages.map { message in
                    LegacyMessageData(
                        content: message.content,
                        role: message.role,
                        timestamp: message.timestamp,
                        runId: message.runId
                    )
                }
            )
        }

        try relocateLegacyStore(at: storeURL)

        let newContainer = try ModelContainer(for: Topic.self, Message.self)
        let newContext = ModelContext(newContainer)

        for projectData in projectsData {
            let topic = Topic(name: projectData.name, conversationKey: projectData.conversationKey)
            topic.createdAt = projectData.createdAt
            topic.lastActiveAt = projectData.lastActiveAt
            newContext.insert(topic)

            for messageData in projectData.messages {
                let message = Message(
                    content: messageData.content,
                    role: Message.Role(rawValue: messageData.role) ?? .assistant,
                    runId: messageData.runId
                )
                message.timestamp = messageData.timestamp
                message.topic = topic
                newContext.insert(message)
            }
        }

        try newContext.save()
        Logger.migration.info("Migrated \(projectsData.count) project(s) to topics.")
    }

    /// Renames the old store files (`.store`, `-wal`, `-shm`) with a
    /// `.legacy-backup` suffix so the new container can claim the default
    /// store URL with a clean slate.
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

/// Plain-value copy of a `LegacyTopicSchema.Message`, safe to hold onto
/// after the backing store file has been moved.
private struct LegacyMessageData {
    let content: String
    let role: String
    let timestamp: Date
    let runId: String?
}

/// Plain-value copy of a `LegacyTopicSchema.Project` and its messages,
/// safe to hold onto after the backing store file has been moved.
private struct LegacyProjectData {
    let name: String
    let conversationKey: String
    let createdAt: Date
    let lastActiveAt: Date
    let messages: [LegacyMessageData]
}
