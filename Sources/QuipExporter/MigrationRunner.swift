import Foundation

@MainActor
class MigrationRunner: ObservableObject {
    @Published var logEntries: [LogEntry] = []
    @Published var isRunning = false

    private var migrationTask: Task<Void, Never>?

    private let blobCache: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("QuipExporter/BlobCache")
    }()

    func start(
        token: String,
        domain: QuipDomain,
        destination: ExportDestination,
        deleteAfterCopy: Bool,
        rateDelay: Double,
        notesAccount: String,
        markdownOutputDir: URL?,
        htmlOutputDir: URL?
    ) {
        guard !isRunning else { return }
        isRunning = true
        logEntries = []

        let blobCache = self.blobCache
        migrationTask = Task.detached { [weak self] in
            let client = QuipClient(token: token, rateDelay: rateDelay, domain: domain)

            func log(_ msg: String, level: LogEntry.Level = .info) async {
                let entry = LogEntry(message: msg, level: level)
                guard let self else { return }
                await MainActor.run { self.logEntries.append(entry) }
            }

            await run(
                client: client,
                destination: destination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                markdownOutputDir: markdownOutputDir,
                htmlOutputDir: htmlOutputDir,
                blobCache: blobCache,
                log: log
            )
            guard let self else { return }
            await MainActor.run { self.isRunning = false }
        }
    }

    func stop() {
        migrationTask?.cancel()
        migrationTask = nil
        logEntries.append(LogEntry(message: "Migration stopped by user.", level: .warning))
        isRunning = false
    }

    func runFormattingTest(notesAccount: String) {
        guard !isRunning else { return }
        isRunning = true
        logEntries = []

        migrationTask = Task.detached { [weak self] in
            func log(_ msg: String, _ level: LogEntry.Level = .info) async {
                let entry = LogEntry(message: msg, level: level)
                guard let self else { return }
                await MainActor.run { self.logEntries.append(entry) }
            }

            let writer = NotesWriter(account: notesAccount)
            do {
                let folderId = try writer.getOrCreateFolder(path: ["From Quip"])
                await log("Creating test note…", .info)
                let (sent, received) = try writer.runFormattingTest(folderId: folderId)
                await log("── SENT HTML ──────────────────────────────────", .info)
                await log(sent, .info)
                await log("── RECEIVED HTML ──────────────────────────────", .info)
                await log(received, .info)
                await log("Test complete.", .info)
            } catch {
                await log("Test failed: \(error.localizedDescription)", .error)
            }

            guard let self else { return }
            await MainActor.run { self.isRunning = false }
        }
    }
}
