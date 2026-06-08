import Foundation
import AppKit

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

            let confirm: ((String, [String]) async -> ExportDestination?)?
            if destination == .ask {
                let hasMarkdown = markdownOutputDir != nil
                let hasHTML = htmlOutputDir != nil
                confirm = { [weak self] title, path in
                    await MainActor.run { [weak self] in
                        let alert = NSAlert()
                        alert.messageText = "Export \"\(title)\"?"
                        let sub = path.count > 1 ? path.dropFirst().joined(separator: " / ") : "Root folder"
                        alert.informativeText = sub
                        // Build buttons in order; track which destination each maps to.
                        var choices: [ExportDestination] = [.appleNotes]
                        alert.addButton(withTitle: "Copy to Notes")
                        if hasMarkdown {
                            alert.addButton(withTitle: "Save as Markdown")
                            choices.append(.markdown)
                        }
                        if hasHTML {
                            alert.addButton(withTitle: "Save as HTML")
                            choices.append(.html)
                        }
                        alert.addButton(withTitle: "Skip")
                        alert.addButton(withTitle: "Stop")
                        let response = alert.runModal()
                        let idx = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                        if idx < choices.count {
                            return choices[idx]
                        }
                        // Skip button
                        if idx == choices.count { return nil }
                        // Stop button
                        self?.stop()
                        return nil
                    }
                }
            } else {
                confirm = nil
            }

            await run(
                client: client,
                destination: destination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                markdownOutputDir: markdownOutputDir,
                htmlOutputDir: htmlOutputDir,
                blobCache: blobCache,
                confirm: confirm,
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
