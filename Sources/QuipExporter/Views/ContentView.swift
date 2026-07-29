import SwiftUI

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
                existingFileBehavior: $existingFileBehavior,
                notesAccount: $notesAccount,
                exportFolder: exportFolder,
                isRunning: runner.isRunning,
                tokenTestResult: runner.tokenTestResult,
                onTestToken: { runner.testToken(token: quipToken, domain: quipDomain) }
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            ResultsPanel(runner: runner, quipDomain: quipDomain)

            Divider()

            ControlBar(
                runner: runner,
                quipToken: quipToken,
                quipDomain: quipDomain,
                documentDestination: documentDestination,
                spreadsheetDestination: spreadsheetDestination,
                deleteAfterCopy: deleteAfterCopy,
                existingFileBehavior: existingFileBehavior,
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
    @Binding var existingFileBehavior: ExistingFileBehavior
    @Binding var notesAccount: String
    @Binding var exportFolder: URL?
    let isRunning: Bool
    let tokenTestResult: TokenTestResult?
    let onTestToken: () -> Void
    @State private var showToken = false
    @State private var showDescription = true

    private var needsExportFolder: Bool {
        documentDestination != .appleNotes || spreadsheetDestination != .appleNotes
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Token")
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

                    Button("Test Token") { onTestToken() }
                }

                if let tokenTestResult {
                    Text(tokenTestResult.message)
                        .foregroundStyle(tokenTestResult.succeeded ? .green : .red)
                        .font(.callout)
                }
            }
            .disabled(isRunning)

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

                HStack {
                    Text("If file already exists")
                    Spacer()
                    Picker("", selection: $existingFileBehavior) {
                        ForEach(ExistingFileBehavior.allCases) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Toggle("Delete private Quip documents after copying", isOn: $deleteAfterCopy)
            }
            .disabled(isRunning)

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation { showDescription.toggle() }
                    } label: {
                        HStack {
                            Text("What does this do?")
                            Spacer()
                            Image(systemName: "chevron.left")
                                .rotationEffect(.degrees(showDescription ? -90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showDescription {
                        Text(migrationDescription(
                            documentDestination: documentDestination,
                            spreadsheetDestination: spreadsheetDestination,
                            deleteAfterCopy: deleteAfterCopy,
                            existingFileBehavior: existingFileBehavior,
                            notesAccount: notesAccount,
                            exportFolder: exportFolder
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(false)
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .onChange(of: isRunning) { newValue in
            if newValue { showDescription = false }
        }
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
    existingFileBehavior: ExistingFileBehavior,
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
        switch existingFileBehavior {
        case .ask:
            parts.append("If one has changed since, you'll be asked whether to overwrite it.")
        case .overwrite:
            parts.append("If one has changed since, it's automatically overwritten with the latest version from Quip.")
        case .ignore:
            parts.append("If one has changed since, it's left as-is.")
        }
    }

    return parts.joined(separator: " ")
}

// MARK: - Results (Summary / Logs)

private enum ResultsTab: String, CaseIterable, Identifiable {
    case files = "Files"
    case summary = "Summary"
    case logs = "Logs"
    var id: String { rawValue }
}

struct ResultsPanel: View {
    @ObservedObject var runner: MigrationRunner
    let quipDomain: QuipDomain
    @State private var tab: ResultsTab = .summary

    var body: some View {
        VStack(spacing: 0) {
            if runner.isRunning {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text(runner.resultsKind == .scan ? "Scanning…" : "Migrating…").foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            Picker("", selection: $tab) {
                ForEach(ResultsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 200)
            .padding(.top, 8)

            switch tab {
            case .files:
                FilesPanel(files: runner.copiedFiles)
            case .summary:
                SummaryView(
                    resultsKind: runner.resultsKind,
                    summary: runner.runSummary,
                    scanSummary: runner.scanSummary,
                    authError: runner.authError,
                    quipDomain: quipDomain
                )
            case .logs:
                LogPanel(entries: runner.logEntries)
            }
        }
        .onChange(of: runner.scanSummary) { newValue in
            if newValue != nil { tab = .summary }
        }
        .onChange(of: runner.authError) { newValue in
            if newValue != nil { tab = .summary }
        }
    }
}

struct SummaryView: View {
    let resultsKind: ResultsKind
    let summary: RunSummary
    let scanSummary: ScanSummary?
    let authError: String?
    let quipDomain: QuipDomain

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
            if let authError {
                Section("Authentication Error") {
                    Text(authError)
                        .foregroundStyle(.red)
                    if authError.contains("Invalid access_token") {
                        HStack {
                            Spacer()
                            Button("Get Token") {
                                NSWorkspace.shared.open(quipDomain.tokenURL)
                            }
                            Spacer()
                        }
                    }
                }
            }
            switch resultsKind {
            case .scan:
                Section("Scan Results") {
                    LabeledContent("Documents to transfer", value: "\(scanSummary?.toTransfer ?? 0)")
                    LabeledContent("Documents to update", value: "\(scanSummary?.toUpdate ?? 0)")
                    LabeledContent("Documents to trash in Quip after copying", value: "\(scanSummary?.toTrash ?? 0)")
                }
            case .export:
                Section("Export Results") {
                    ForEach(rows, id: \.0) { label, value in
                        LabeledContent(label) {
                            Text("\(value)")
                                .foregroundStyle(label == "Errors" && value > 0 ? .red : .primary)
                        }
                    }
                }
            case .none:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Files

struct FilesPanel: View {
    let files: [CopiedFile]

    var body: some View {
        if files.isEmpty {
            Text("No files copied yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(files) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.directory)
                        .foregroundStyle(.secondary)
                    Text(file.file)
                        .padding(.leading, 16)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    let existingFileBehavior: ExistingFileBehavior
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
                Text(runner.logEntries.isEmpty ? " " : "\(runner.logEntries.count) log entries")
                    .foregroundStyle(.secondary)
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
                            exportFolder: exportFolder,
                            existingFileBehavior: existingFileBehavior
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
