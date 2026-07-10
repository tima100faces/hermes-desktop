import Foundation
import os

// MARK: - GitSyncResult

/// The result of a `git pull --ff-only` operation performed by `GitSyncService`.
///
/// The caller inspects this value to determine what happened — it is **not**
/// an error type. All sync outcomes are non-throwing and expressed through
/// this enum instead.
public enum GitSyncResult: Equatable {
    /// The pull completed and new changes were fetched.
    case success(output: String)
    /// The local repository was already up to date.
    case noChanges
    /// The pull failed (e.g. merge conflict, network error, timeout).
    case failed(error: String)
    /// The `git` executable was not found at `/usr/bin/git`.
    case gitNotFound
}

// MARK: - GitSyncService

/// Performs `git pull --ff-only` inside `~/Projects/agents-hub`.
///
/// ## Fire-and-forget
///
/// Failures are logged and reported via `GitSyncResult` but never thrown.
/// This is intentional: a sync failure **must not** block app launch or
/// propagate to the user as a crash.
///
/// ## Concurrency
///
/// `GitSyncService` is a `public actor`, so all calls to `sync()` are
/// mutually exclusive within a single instance. The underlying `Process`
/// is launched inside a `withCheckedContinuation` bridge so the actor
/// executor is never blocked by `waitUntilExit()`.
public actor GitSyncService {

    // MARK: - Constants

    private static let gitPath = "/usr/bin/git"
    private static let agentsHubRelativePath = "Projects/agents-hub"
    private static let syncTimeout: TimeInterval = 30

    // MARK: - Logger

    private let logger = Logger(
        subsystem: "com.hermes-desktop",
        category: "git-sync"
    )

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Runs `git pull --ff-only` in `~/Projects/agents-hub`.
    ///
    /// - Returns: A `GitSyncResult` describing the outcome.
    public func sync() async -> GitSyncResult {
        let agentsHubPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.agentsHubRelativePath)
            .path(percentEncoded: false)

        // --- Graceful degradation: git not installed -------------------------
        guard FileManager.default.isExecutableFile(atPath: Self.gitPath) else {
            logger.warning("Git executable not found at \(Self.gitPath)")
            return .gitNotFound
        }

        // --- Configure Process -----------------------------------------------
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.gitPath)
        process.arguments = ["pull", "--ff-only"]
        process.currentDirectoryURL = URL(fileURLWithPath: agentsHubPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // --- Bridge Process (non-Sendable) into async world ------------------
        return await withCheckedContinuation { continuation in
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + Self.syncTimeout)
            timer.setEventHandler { [weak process] in
                process?.terminate()
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result: GitSyncResult

                if proc.terminationStatus == 0 {
                    // Exit code 0 — pull succeeded (or was a no-op).
                    let output = stdout.isEmpty ? stderr : stdout
                    if output.contains("Already up to date") {
                        result = .noChanges
                    } else {
                        result = .success(output: output)
                    }
                } else {
                    // Non-zero exit — pull failed.
                    if proc.terminationReason == .uncaughtSignal {
                        result = .failed(error: "timeout")
                    } else {
                        let errorMsg = stderr.isEmpty
                            ? "exit code \(proc.terminationStatus)"
                            : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        result = .failed(error: errorMsg)
                    }
                }

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                let result = GitSyncResult.failed(error: error.localizedDescription)
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - Convenience (optional, kept small)

extension GitSyncResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .success(let output):
            return "sync succeeded: \(output)"
        case .noChanges:
            return "sync no-op: already up to date"
        case .failed(let error):
            return "sync failed: \(error)"
        case .gitNotFound:
            return "sync skipped: git not found"
        }
    }
}
