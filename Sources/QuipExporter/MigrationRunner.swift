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
        markdownOutputDir: URL?
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
}
