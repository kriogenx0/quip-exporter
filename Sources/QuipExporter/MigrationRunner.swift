import Foundation
import AppKit

// Boxes the "apply to all remaining items" choice so the confirmOverwrite closure
// can persist it across calls without capturing a mutable var in a @Sendable closure.
private final class OverwriteBatch {
    var choice: OverwriteChoice?
}

// Shells out to /usr/bin/diff so overwrite confirmations can show exactly what would
// change, using the same unified-diff format developers already read day to day.
private func unifiedDiff(old: String, new: String) -> String {
    let tmp = FileManager.default.temporaryDirectory
    let oldFile = tmp.appendingPathComponent(UUID().uuidString)
    let newFile = tmp.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: oldFile)
        try? FileManager.default.removeItem(at: newFile)
    }
    do {
        try old.write(to: oldFile, atomically: true, encoding: .utf8)
        try new.write(to: newFile, atomically: true, encoding: .utf8)
    } catch {
        return "(could not compute diff: \(error.localizedDescription))"
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
    proc.arguments = ["-u", "--label", "existing", "--label", "from Quip", oldFile.path, newFile.path]
    let pipe = Pipe()
    proc.standardOutput = pipe
    do {
        try proc.run()
    } catch {
        return "(diff unavailable: \(error.localizedDescription))"
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.isEmpty ? "No differences." : output
}

// A scrollable, read-only monospaced text view sized for diff output in an NSAlert.
private func diffAccessoryView(_ text: String) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.frame = NSRect(x: 0, y: 0, width: 560, height: 320)
    scrollView.hasVerticalScroller = true
    if let textView = scrollView.documentView as? NSTextView {
        textView.string = text
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    }
    return scrollView
}

@MainActor
class MigrationRunner: ObservableObject {
    @Published var logEntries: [LogEntry] = []
    @Published var isRunning = false
    @Published var runSummary = RunSummary()
    @Published var scanSummary: ScanSummary?

    private var migrationTask: Task<Void, Never>?

    private let blobCache: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("QuipExporter/BlobCache")
    }()

    func start(
        token: String,
        domain: QuipDomain,
        documentDestination: ExportDestination,
        spreadsheetDestination: ExportDestination,
        deleteAfterCopy: Bool,
        rateDelay: Double,
        notesAccount: String,
        exportFolder: URL?
    ) {
        guard !isRunning else { return }
        isRunning = true
        logEntries = []
        runSummary = RunSummary()
        scanSummary = nil

        let blobCache = self.blobCache
        migrationTask = Task.detached { [weak self] in
            let client = QuipClient(token: token, rateDelay: rateDelay, domain: domain)

            func log(_ msg: String, level: LogEntry.Level = .info) async {
                let entry = LogEntry(message: msg, level: level)
                guard let self else { return }
                await MainActor.run { self.logEntries.append(entry) }
            }

            func count(_ event: RunEvent) async {
                guard let self else { return }
                await MainActor.run {
                    switch event {
                    case .folder: self.runSummary.foldersVisited += 1
                    case .transferred: self.runSummary.documentsTransferred += 1
                    case .updated: self.runSummary.documentsUpdated += 1
                    case .unchanged: self.runSummary.documentsUnchanged += 1
                    case .skipped: self.runSummary.documentsSkipped += 1
                    case .trashed: self.runSummary.documentsTrashed += 1
                    case .error: self.runSummary.errors += 1
                    }
                }
            }

            let confirm: ((String, [String], Bool) async -> ExportDestination?)?
            if documentDestination == .ask || spreadsheetDestination == .ask {
                let hasFolder = exportFolder != nil
                confirm = { [weak self] title, path, isSpreadsheet in
                    await MainActor.run { [weak self] in
                        let alert = NSAlert()
                        alert.messageText = "Export \"\(title)\"?"
                        let sub = path.count > 1 ? path.dropFirst().joined(separator: " / ") : "Root folder"
                        alert.informativeText = sub
                        // Build buttons in order; track which destination each maps to.
                        var choices: [ExportDestination] = [.appleNotes]
                        alert.addButton(withTitle: "Copy to Notes")
                        if isSpreadsheet && hasFolder {
                            alert.addButton(withTitle: "Save as Numbers")
                            choices.append(.numbers)
                        }
                        if isSpreadsheet && hasFolder {
                            alert.addButton(withTitle: "Save as CSV")
                            choices.append(.csv)
                        }
                        if hasFolder {
                            alert.addButton(withTitle: "Save as Markdown")
                            choices.append(.markdown)
                        }
                        if hasFolder {
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

            let batch = OverwriteBatch()
            let confirmOverwrite: (String, [String], String?, String?) async -> OverwriteChoice = { [weak self] title, path, oldContent, newContent in
                if let choice = batch.choice { return choice }
                return await MainActor.run { [weak self] in
                    let alert = NSAlert()
                    alert.messageText = "\"\(title)\" already exists"
                    let sub = path.count > 1 ? path.dropFirst().joined(separator: " / ") : "Root folder"
                    alert.informativeText = "\(sub)\n\nOverwrite it with the latest version from Quip, or skip it?"
                    if let newContent {
                        if let oldContent {
                            alert.accessoryView = diffAccessoryView(unifiedDiff(old: oldContent, new: newContent))
                        } else {
                            alert.accessoryView = diffAccessoryView("(existing content can't be read for a diff — preview of what would be written)\n\n" + newContent)
                        }
                    }
                    alert.addButton(withTitle: "Overwrite")
                    alert.addButton(withTitle: "Overwrite All")
                    alert.addButton(withTitle: "Skip")
                    alert.addButton(withTitle: "Skip All")
                    alert.addButton(withTitle: "Stop")
                    let response = alert.runModal()
                    switch response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
                    case 0: return .overwrite
                    case 1: batch.choice = .overwrite; return .overwrite
                    case 2: return .skip
                    case 3: batch.choice = .skip; return .skip
                    default: self?.stop(); return .stop
                    }
                }
            }

            await run(
                client: client,
                documentDestination: documentDestination,
                spreadsheetDestination: spreadsheetDestination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                exportFolder: exportFolder,
                blobCache: blobCache,
                confirm: confirm,
                confirmOverwrite: confirmOverwrite,
                count: count,
                log: log
            )
            guard let self else { return }
            await MainActor.run { self.isRunning = false }
        }
    }

    func scanAccount(
        token: String,
        domain: QuipDomain,
        documentDestination: ExportDestination,
        spreadsheetDestination: ExportDestination,
        deleteAfterCopy: Bool,
        rateDelay: Double,
        notesAccount: String,
        exportFolder: URL?
    ) {
        guard !isRunning else { return }
        isRunning = true
        logEntries = []
        scanSummary = nil

        migrationTask = Task.detached { [weak self] in
            let client = QuipClient(token: token, rateDelay: rateDelay, domain: domain)

            func log(_ msg: String, level: LogEntry.Level = .info) async {
                let entry = LogEntry(message: msg, level: level)
                guard let self else { return }
                await MainActor.run { self.logEntries.append(entry) }
            }

            let summary = await scan(
                client: client,
                documentDestination: documentDestination,
                spreadsheetDestination: spreadsheetDestination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                exportFolder: exportFolder,
                log: log
            )

            guard let self else { return }
            await MainActor.run {
                self.scanSummary = summary
                self.isRunning = false
            }
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
