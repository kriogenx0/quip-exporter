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
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Quip Export").path
    }

    private var exportFolder: Binding<URL?> {
        Binding(
            get: { exportFolderPath.isEmpty ? nil : URL(fileURLWithPath: exportFolderPath) },
            set: { exportFolderPath = $0?.path ?? "" }
        )
    }

    @StateObject private var runner = MigrationRunner()
    @State private var logsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView {
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
                }
                .frame(width: 320)

                Divider()

                ResultsPanel(runner: runner, quipDomain: quipDomain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            BottomBar(
                runner: runner,
                quipToken: quipToken,
                quipDomain: quipDomain,
                documentDestination: documentDestination,
                spreadsheetDestination: spreadsheetDestination,
                deleteAfterCopy: deleteAfterCopy,
                existingFileBehavior: existingFileBehavior,
                notesAccount: notesAccount,
                exportFolder: exportFolder.wrappedValue,
                logsExpanded: $logsExpanded
            )
        }
        .frame(minWidth: 850, minHeight: 600)
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
    @State private var showDescription = true
    @State private var showPasteTokenSheet = false

    private var needsExportFolder: Bool {
        documentDestination != .appleNotes || spreadsheetDestination != .appleNotes
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Token", selection: $quipDomain) {
                        ForEach(QuipDomain.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Button("Get Token") {
                            NSWorkspace.shared.open(quipDomain.tokenURL)
                            showPasteTokenSheet = true
                        }
                        Button("Test Token") { onTestToken() }
                    }
                }

                if let tokenTestResult {
                    Text(tokenTestResult.message)
                        .foregroundStyle(tokenTestResult.succeeded ? .green : .red)
                        .font(.callout)
                }
            }
            .disabled(isRunning)

            Section {
                Picker("Documents", selection: $documentDestination) {
                    ForEach(ExportDestination.allCases.filter { $0 != .numbers && $0 != .csv }) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.menu)

                Picker("Spreadsheets", selection: $spreadsheetDestination) {
                    ForEach(ExportDestination.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.menu)

                if needsExportFolder {
                    FolderPickerRow(label: "Export Folder", url: $exportFolder)
                }

                Picker("If file already exists", selection: $existingFileBehavior) {
                    ForEach(ExistingFileBehavior.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.menu)

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
        .sheet(isPresented: $showPasteTokenSheet) {
            PasteTokenSheet(
                onPaste: {
                    showPasteTokenSheet = false
                    if let pasted = NSPasteboard.general.string(forType: .string) {
                        quipToken = pasted
                        onTestToken()
                    }
                },
                onCancel: { showPasteTokenSheet = false }
            )
        }
    }
}

// MARK: - Paste Token Sheet

private struct PasteTokenSheet: View {
    let onPaste: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste Your Token")
                .font(.headline)
            Text("Copy the token from the page that just opened in your browser, then paste it in below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Paste Token") { onPaste() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct FolderPickerRow: View {
    let label: String
    @Binding var url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
            HStack {
                Text(url?.path ?? "Not configured")
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                Spacer()
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
    let folder = exportFolder.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
    switch destination {
    case .appleNotes:
        let account = notesAccount.isEmpty ? "your default Notes account" : "the \"\(notesAccount)\" account"
        return "\(category) are copied from your Quip account (Desktop, Starred, and Shared folders) into \(account) under a top-level \"Quip Export\" folder, preserving the folder hierarchy. Desktop, Starred, and Private folders are flattened into the root."
    case .numbers:
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as native Numbers documents inside \(folder), preserving the folder hierarchy."
    case .csv:
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as CSV files inside \(folder), preserving the folder hierarchy. Each spreadsheet becomes a folder with one CSV file per tab."
    case .markdown:
        return "\(category) are exported from your Quip account (Desktop, Starred, and Shared folders) as Markdown files inside \(folder), preserving the folder hierarchy. Images are saved alongside each file in an _assets/ subfolder."
    case .html:
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

// MARK: - Results (Summary above Files)

struct ResultsPanel: View {
    @ObservedObject var runner: MigrationRunner
    let quipDomain: QuipDomain

    private var hasSummary: Bool {
        runner.resultsKind != .none || runner.authError != nil
    }

    // Only meaningful during a real export, and only once a same-session Scan has told
    // us how many documents there are to transfer — otherwise there's no total to show
    // progress against, so callers fall back to an indeterminate spinner.
    private var transferProgress: (current: Int, total: Int)? {
        guard runner.resultsKind == .export, let total = runner.scanSummary?.toTransfer, total > 0 else { return nil }
        return (runner.runSummary.documentsTransferred, total)
    }

    var body: some View {
        VStack(spacing: 0) {
            if runner.isRunning {
                if let progress = transferProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                        Text("\(progress.current) of \(progress.total) files transferred")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text(runner.resultsKind == .scan ? "Scanning…" : "Migrating…").foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }

            if hasSummary {
                SummaryView(
                    resultsKind: runner.resultsKind,
                    summary: runner.runSummary,
                    scanSummary: runner.scanSummary,
                    authError: runner.authError,
                    quipDomain: quipDomain
                )
                .fixedSize(horizontal: false, vertical: true)

                Divider()
            }

            FilesPanel(files: runner.copiedFiles)
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
                    HStack(spacing: 12) {
                        StatCard(title: "To Transfer", value: scanSummary?.toTransfer ?? 0)
                        StatCard(title: "To Update", value: scanSummary?.toUpdate ?? 0)
                        StatCard(title: "To Trash in Quip", value: scanSummary?.toTrash ?? 0)
                    }
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
        .frame(maxWidth: .infinity)
    }
}

private struct StatCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 26, weight: .semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Files

struct FilesPanel: View {
    let files: [CopiedFile]

    private struct Group: Identifiable {
        let id = UUID()
        let directory: String
        var files: [CopiedFile]
    }

    // Splits into runs of consecutive files sharing a directory, rather than merging
    // every occurrence of a directory name — so a directory revisited later in the
    // (unsorted, traversal-order) list gets its own header instead of merging back
    // into an earlier, non-adjacent run.
    private var groups: [Group] {
        var result: [Group] = []
        for file in files {
            if result.indices.last.map({ result[$0].directory == file.directory }) == true {
                result[result.count - 1].files.append(file)
            } else {
                result.append(Group(directory: file.directory, files: [file]))
            }
        }
        return result
    }

    var body: some View {
        if files.isEmpty {
            Text("No files copied yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.files) { file in
                                    HStack {
                                        statusIcon(file.status)
                                        Text(file.file)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } header: {
                                Text(group.directory)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.bar)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .onChange(of: files.count) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: FileStatus) -> some View {
        switch status {
        case .copied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
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

// MARK: - Bottom bar (status, actions, and collapsible logs)

struct BottomBar: View {
    @ObservedObject var runner: MigrationRunner
    let quipToken: String
    let quipDomain: QuipDomain
    let documentDestination: ExportDestination
    let spreadsheetDestination: ExportDestination
    let deleteAfterCopy: Bool
    let existingFileBehavior: ExistingFileBehavior
    let notesAccount: String
    let exportFolder: URL?
    @Binding var logsExpanded: Bool

    private var canStart: Bool {
        guard !quipToken.isEmpty else { return false }
        let categories = [documentDestination, spreadsheetDestination]
        let needsFolder = categories.contains(.markdown) || categories.contains(.html)
            || spreadsheetDestination == .numbers || spreadsheetDestination == .csv
        if needsFolder, exportFolder == nil { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            if logsExpanded {
                LogPanel(entries: runner.logEntries)
                    .frame(height: 220)
                Divider()
            }

            ZStack {
                // Status anchored to the leading edge
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { logsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .rotationEffect(.degrees(logsExpanded ? 180 : 0))
                            Text(runner.logEntries.isEmpty ? "Logs" : "Logs (\(runner.logEntries.count))")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if logsExpanded && !runner.logEntries.isEmpty {
                        Button("Save…") { saveLog() }
                        Button("Clear") { runner.logEntries = [] }
                    }

                    Spacer()

                    Text(runner.copiedFiles.isEmpty ? " " : "\(runner.copiedFiles.count) total files")
                        .foregroundStyle(.secondary)

                    #if DEBUG
                    if !runner.isRunning && (documentDestination == .appleNotes || spreadsheetDestination == .appleNotes) {
                        Button("Create Test Note") {
                            runner.runFormattingTest(notesAccount: notesAccount)
                        }
                    }
                    #endif
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
