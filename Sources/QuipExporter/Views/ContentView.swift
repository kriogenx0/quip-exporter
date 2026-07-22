import SwiftUI

struct ContentView: View {
    @AppStorage("quipToken") private var quipToken = ""
    @AppStorage("quipDomain") private var quipDomain: QuipDomain = .quipApple
    @AppStorage("documentDestination") private var documentDestination: ExportDestination = .appleNotes
    @AppStorage("spreadsheetDestination") private var spreadsheetDestination: ExportDestination = .appleNotes
    @AppStorage("deleteAfterCopy") private var deleteAfterCopy = false
    @AppStorage("notesAccount") private var notesAccount = ""
    @AppStorage("exportFolderPath") private var exportFolderPath = Self.defaultExportFolderPath

    private static var defaultExportFolderPath: String {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?
            .appendingPathComponent("QuipDocuments").path ?? ""
    }

    private var exportFolder: Binding<URL?> {
        Binding(
            get: { exportFolderPath.isEmpty ? nil : URL(fileURLWithPath: exportFolderPath) },
            set: { exportFolderPath = $0?.path ?? "" }
        )
    }

    @StateObject private var runner = MigrationRunner()

    var body: some View {
        VStack(spacing: 0) {
            SettingsPanel(
                quipToken: $quipToken,
                quipDomain: $quipDomain,
                documentDestination: $documentDestination,
                spreadsheetDestination: $spreadsheetDestination,
                deleteAfterCopy: $deleteAfterCopy,
                notesAccount: $notesAccount,
                exportFolder: exportFolder,
                isRunning: runner.isRunning
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            ResultsPanel(runner: runner)

            Divider()

            ControlBar(
                runner: runner,
                quipToken: quipToken,
                quipDomain: quipDomain,
                documentDestination: documentDestination,
                spreadsheetDestination: spreadsheetDestination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                exportFolder: exportFolder.wrappedValue
            )
        }
        .frame(minWidth: 650, minHeight: 550)
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @Binding var quipToken: String
    @Binding var quipDomain: QuipDomain
    @Binding var documentDestination: ExportDestination
    @Binding var spreadsheetDestination: ExportDestination
    @Binding var deleteAfterCopy: Bool
    @Binding var notesAccount: String
    @Binding var exportFolder: URL?
    let isRunning: Bool
    @State private var showToken = false
    @State private var showDescription = false

    private var needsExportFolder: Bool {
        documentDestination != .appleNotes || spreadsheetDestination != .appleNotes
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Platform")
                    Spacer()
                    Picker("", selection: $quipDomain) {
                        ForEach(QuipDomain.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    Link("Get token", destination: quipDomain.tokenURL)
                        .font(.body)
                }

                HStack {
                    TokenField(text: $quipToken, isSecure: !showToken)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22)

                    Button { showToken.toggle() } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                HStack {
                    Text("Documents")
                    Spacer()
                    Picker("", selection: $documentDestination) {
                        ForEach(ExportDestination.allCases.filter { $0 != .numbers && $0 != .csv }) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                HStack {
                    Text("Spreadsheets")
                    Spacer()
                    Picker("", selection: $spreadsheetDestination) {
                        ForEach(ExportDestination.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                if needsExportFolder {
                    FolderPickerRow(label: "Export Folder", url: $exportFolder)
                }

                Toggle("Delete private Quip documents after copying", isOn: $deleteAfterCopy)

                DisclosureGroup("What does this do?", isExpanded: $showDescription) {
                    Text(migrationDescription(
                        documentDestination: documentDestination,
                        spreadsheetDestination: spreadsheetDestination,
                        deleteAfterCopy: deleteAfterCopy,
                        notesAccount: notesAccount,
                        exportFolder: exportFolder
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(isRunning)
        .padding(.horizontal, 4)
    }
}

private struct FolderPickerRow: View {
    let label: String
    @Binding var url: URL?

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(url?.path ?? "Not configured")
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                Button(url == nil ? "Configure…" : "Change…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK { url = panel.url }
                }
            }
        }
    }
}

// MARK: - Migration info banner

private func describe(_ destination: ExportDestination, category: String, notesAccount: String, exportFolder: URL?) -> String {
    switch destination {
    case .appleNotes:
        let account = notesAccount.isEmpty ? "your default Notes account" : "the \"\(notesAccount)\" account"
        return "\(category) are copied from your Quip account (Desktop, Starred, and Shared folders) into \(account) under a top-level \"From Quip\" folder, preserving the folder hierarchy. Desktop, Starred, and Private folders are flattened into the root."
    case .numbers:
        let folder = exportFolder.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as native Numbers documents inside \(folder), preserving the folder hierarchy."
    case .csv:
        let folder = exportFolder.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as CSV files inside \(folder), preserving the folder hierarchy. Each spreadsheet becomes a folder with one CSV file per tab."
    case .markdown:
        let folder = exportFolder.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as Markdown files inside \(folder), preserving the folder hierarchy. Images are saved alongside each file in an _assets/ subfolder."
    case .html:
        let folder = exportFolder.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as HTML files inside \(folder), preserving the folder hierarchy. Images are saved alongside each file in an _assets/ subfolder."
    case .ask:
        return "For each \(category.lowercased()), asks where to export it (configure the export folder above to enable more options)."
    }
}

private func migrationDescription(
    documentDestination: ExportDestination,
    spreadsheetDestination: ExportDestination,
    deleteAfterCopy: Bool,
    notesAccount: String,
    exportFolder: URL?
) -> String {
    var parts: [String] = []

    if documentDestination == spreadsheetDestination {
        parts.append(describe(documentDestination, category: "Documents and spreadsheets", notesAccount: notesAccount, exportFolder: exportFolder))
    } else {
        parts.append(describe(documentDestination, category: "Documents", notesAccount: notesAccount, exportFolder: exportFolder))
        parts.append(describe(spreadsheetDestination, category: "Spreadsheets", notesAccount: notesAccount, exportFolder: exportFolder))
    }

    if deleteAfterCopy {
        parts.append("Private (unshared) documents will be moved to Quip Trash after copying.")
    }

    var skipNote: [String] = []
    if documentDestination != .ask { skipNote.append("documents") }
    if spreadsheetDestination != .ask { skipNote.append("spreadsheets") }
    if !skipNote.isEmpty {
        parts.append("Already-exported \(skipNote.joined(separator: " and ")) are skipped on re-runs.")
    }

    return parts.joined(separator: " ")
}

// MARK: - Results (Summary / Logs)

private enum ResultsTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case logs = "Logs"
    var id: String { rawValue }
}

struct ResultsPanel: View {
    @ObservedObject var runner: MigrationRunner
    @State private var tab: ResultsTab = .logs

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(ResultsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200)
            .padding(.top, 8)

            switch tab {
            case .summary:
                SummaryView(summary: runner.runSummary)
            case .logs:
                LogPanel(entries: runner.logEntries)
            }
        }
    }
}

struct SummaryView: View {
    let summary: RunSummary

    private var rows: [(String, Int)] {
        [
            ("Folders found", summary.foldersVisited),
            ("Documents transferred", summary.documentsTransferred),
            ("Documents updated", summary.documentsUpdated),
            ("Documents unchanged", summary.documentsUnchanged),
            ("Documents skipped", summary.documentsSkipped),
            ("Documents trashed in Quip", summary.documentsTrashed),
            ("Errors", summary.errors),
        ]
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { label, value in
                    LabeledContent(label) {
                        Text("\(value)")
                            .foregroundStyle(label == "Errors" && value > 0 ? .red : .primary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Log

struct LogPanel: View {
    let entries: [LogEntry]

    var body: some View {
        LogView(entries: entries)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Control bar

struct ControlBar: View {
    @ObservedObject var runner: MigrationRunner
    let quipToken: String
    let quipDomain: QuipDomain
    let documentDestination: ExportDestination
    let spreadsheetDestination: ExportDestination
    let deleteAfterCopy: Bool
    let notesAccount: String
    let exportFolder: URL?

    private var canStart: Bool {
        guard !quipToken.isEmpty else { return false }
        let categories = [documentDestination, spreadsheetDestination]
        let needsFolder = categories.contains(.markdown) || categories.contains(.html)
            || spreadsheetDestination == .numbers || spreadsheetDestination == .csv
        if needsFolder, exportFolder == nil { return false }
        return true
    }

    var body: some View {
        ZStack {
            // Status anchored to the leading edge
            HStack {
                if runner.isRunning {
                    ProgressView().scaleEffect(0.7)
                    Text("Migrating…").foregroundStyle(.secondary)
                } else {
                    Text(runner.logEntries.isEmpty ? " " : "\(runner.logEntries.count) log entries")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !runner.isRunning && !runner.logEntries.isEmpty {
                    Button("Save Log") { saveLog() }
                    Button("Clear Log") { runner.logEntries = [] }
                }
                if !runner.isRunning && (documentDestination == .appleNotes || spreadsheetDestination == .appleNotes) {
                    Button("Create Test Note") {
                        runner.runFormattingTest(notesAccount: notesAccount)
                    }
                }
            }

            // Buttons centered independently
            if runner.isRunning {
                Button("Stop", role: .destructive) { runner.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                HStack {
                    if !quipToken.isEmpty {
                        Button("Scan") {
                            runner.scanAccount(
                                token: quipToken,
                                domain: quipDomain,
                                documentDestination: documentDestination,
                                spreadsheetDestination: spreadsheetDestination,
                                deleteAfterCopy: deleteAfterCopy,
                                rateDelay: 0.5,
                                notesAccount: notesAccount,
                                exportFolder: exportFolder
                            )
                        }
                    }
                    Button {
                        runner.start(
                            token: quipToken,
                            domain: quipDomain,
                            documentDestination: documentDestination,
                            spreadsheetDestination: spreadsheetDestination,
                            deleteAfterCopy: deleteAfterCopy,
                            rateDelay: 0.5,
                            notesAccount: notesAccount,
                            exportFolder: exportFolder
                        )
                    } label: {
                        Label("Start Exporting", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
