import SwiftUI
import AppKit

struct ContentView: View {
    @AppStorage("quipToken") private var quipToken = ""
    @AppStorage("quipDomain") private var quipDomain: QuipDomain = .quipApple
    @AppStorage("documentDestination") private var documentDestination: ExportDestination = .appleNotes
    @AppStorage("spreadsheetDestination") private var spreadsheetDestination: ExportDestination = .appleNotes
    @AppStorage("deleteAfterCopy") private var deleteAfterCopy = false
    @AppStorage("existingFileBehavior") private var existingFileBehavior: ExistingFileBehavior = .ask
    @AppStorage("notesAccount") private var notesAccount = ""
    @AppStorage("exportFolderPath") private var exportFolderPath = Self.defaultExportFolderPath

    private static var defaultExportFolderPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("QuipDocuments").path
    }

    private var exportFolder: Binding<URL?> {
        Binding(
            get: { exportFolderPath.isEmpty ? nil : URL(fileURLWithPath: exportFolderPath) },
            set: { exportFolderPath = $0?.path ?? "" }
        )
    }

    @StateObject private var runner = MigrationRunner()

    private var canStart: Bool {
        guard !quipToken.isEmpty else { return false }
        let categories = [documentDestination, spreadsheetDestination]
        let needsFolder = categories.contains(.markdown) || categories.contains(.html)
            || spreadsheetDestination == .numbers || spreadsheetDestination == .csv
        if needsFolder, exportFolder.wrappedValue == nil { return false }
        return true
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                quipToken: $quipToken,
                quipDomain: $quipDomain,
                documentDestination: $documentDestination,
                spreadsheetDestination: $spreadsheetDestination,
                deleteAfterCopy: $deleteAfterCopy,
                existingFileBehavior: $existingFileBehavior,
                notesAccount: notesAccount,
                exportFolder: exportFolder,
                isRunning: runner.isRunning,
                canStart: canStart,
                tokenTestResult: runner.tokenTestResult,
                onTestToken: { runner.testToken(token: quipToken, domain: quipDomain) },
                onScan: {
                    runner.scanAccount(
                        token: quipToken,
                        domain: quipDomain,
                        documentDestination: documentDestination,
                        spreadsheetDestination: spreadsheetDestination,
                        deleteAfterCopy: deleteAfterCopy,
                        rateDelay: 0.5,
                        notesAccount: notesAccount,
                        exportFolder: exportFolder.wrappedValue
                    )
                },
                onExport: {
                    runner.start(
                        token: quipToken,
                        domain: quipDomain,
                        documentDestination: documentDestination,
                        spreadsheetDestination: spreadsheetDestination,
                        deleteAfterCopy: deleteAfterCopy,
                        rateDelay: 0.5,
                        notesAccount: notesAccount,
                        exportFolder: exportFolder.wrappedValue,
                        existingFileBehavior: existingFileBehavior
                    )
                },
                onStop: { runner.stop() }
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 340)
        } detail: {
            DetailView(runner: runner, quipDomain: quipDomain)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Save Log…") { saveLog() }
                        .disabled(runner.logEntries.isEmpty)
                    Button("Clear Log") { runner.logEntries = [] }
                        .disabled(runner.logEntries.isEmpty)
                    Divider()
                    Button("Create Test Note") {
                        runner.runFormattingTest(notesAccount: notesAccount)
                    }
                    .disabled(documentDestination != .appleNotes && spreadsheetDestination != .appleNotes)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(runner.isRunning)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "quip-export.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let header = "Quip Export — \(Date().formatted(date: .long, time: .standard))"
        let lines = runner.logEntries.map { entry in
            let ts = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .none, timeStyle: .medium)
            return "\(ts)  \(entry.message)"
        }
        let text = ([header, String(repeating: "-", count: header.count)] + lines).joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
