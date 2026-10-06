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
                    onTestToken: { token in runner.testToken(token: token, domain: quipDomain) }
                )
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
        .onChange(of: quipToken) { _ in runner.tokenTestResult = nil }
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
    let onTestToken: (String) -> Void
    @State private var showDescription = true
    @State private var showPasteToken = false
    @State private var pasteError: String?
    @State private var isTestingPaste = false

    private var tokenIsValid: Bool { tokenTestResult?.succeeded == true }

    private var needsExportFolder: Bool {
        documentDestination != .appleNotes || spreadsheetDestination != .appleNotes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow("Token") {
                        Picker("Token", selection: $quipDomain) {
                            ForEach(QuipDomain.allCases) { d in
                                Text(d.rawValue).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    HStack {
                        Button("Get Token") {
                            NSWorkspace.shared.open(quipDomain.tokenURL)
                            withAnimation { showPasteToken = true }
                        }
                        if isTestingPaste {
                            ProgressView().controlSize(.small)
                        } else if tokenIsValid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .help("Token is valid")
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .help(quipToken.isEmpty ? "No token yet" : "Token hasn't been validated")
                        }
                    }

                    // Only a validated token lets the area collapse; until then it stays open.
                    Button {
                        withAnimation { showPasteToken.toggle() }
                    } label: {
                        HStack {
                            Text("Opens your Quip token page. Paste the token here to sign in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showPasteToken ? -90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(showPasteToken && !tokenIsValid)

                    if showPasteToken {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Paste Token") { pasteAndTest() }
                                .disabled(isTestingPaste)

                            Text(quipToken.isEmpty ? "No token yet" : quipToken)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(quipToken.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                            if let pasteError {
                                Text(pasteError)
                                    .foregroundStyle(.red)
                                    .font(.system(.callout, design: .monospaced))
                            } else if let tokenTestResult, !tokenTestResult.succeeded {
                                Text(tokenTestResult.message)
                                    .foregroundStyle(.red)
                                    .font(.system(.callout, design: .monospaced))
                            }
                        }
                    }
                }
                .disabled(isRunning)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    SettingRow("Documents") {
                        Picker("Documents", selection: $documentDestination) {
                            ForEach(ExportDestination.allCases.filter { $0 != .numbers && $0 != .csv }) { d in
                                Text(d.rawValue).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    SettingRow("Spreadsheets") {
                        Picker("Spreadsheets", selection: $spreadsheetDestination) {
                            ForEach(ExportDestination.allCases) { d in
                                Text(d.rawValue).tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    if needsExportFolder {
                        FolderPickerRow(label: "Export Folder", url: $exportFolder)
                    }

                    SettingRow("If file already exists") {
                        Picker("If file already exists", selection: $existingFileBehavior) {
                            ForEach(ExistingFileBehavior.allCases) { b in
                                Text(b.rawValue).tag(b)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Toggle("Delete private Quip documents after copying", isOn: $deleteAfterCopy)
                }
                .disabled(isRunning)

                Divider()

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
            .padding(16)
        }
        .onChange(of: isRunning) { newValue in
            if newValue { showDescription = false }
        }
        .onAppear {
            if !quipToken.isEmpty, tokenTestResult == nil { onTestToken(quipToken) }
        }
        .onChange(of: tokenTestResult?.message) { message in
            guard message != nil, isTestingPaste else { return }
            isTestingPaste = false
            if tokenTestResult?.succeeded == true {
                withAnimation { showPasteToken = false }
            }
        }
    }

    // Pastes the clipboard and tests it straight away. A valid token collapses the
    // paste section (see onChange above); an invalid one leaves it open with the error.
    private func pasteAndTest() {
        let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            pasteError = "The clipboard has no text. Copy the token from your browser first."
            return
        }
        pasteError = nil
        quipToken = pasted
        isTestingPaste = true
        onTestToken(pasted)
    }
}

// A setting with its label stacked above the control, since the sidebar is too narrow for
// inline labels once the plain (non-Form) layout is used.
private struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct FolderPickerRow: View {
    let label: String
    @Binding var url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Text(url?.path ?? "Not configured")
                    .font(.caption)
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

    private var indeterminateLabel: String {
        if runner.resultsKind == .scan { return "Scanning…" }
        let done = runner.runSummary.documentsTransferred
        return done > 0 ? "Exporting… \(done) files transferred" : "Exporting…"
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
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView().progressViewStyle(.linear)
                        Text(indeterminateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
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
                    HStack(spacing: 8) {
                        StatCard(title: "To Transfer", value: scanSummary?.toTransfer ?? 0)
                        StatCard(title: "To Update", value: scanSummary?.toUpdate ?? 0)
                        StatCard(title: "To Trash in Quip", value: scanSummary?.toTrash ?? 0)
                    }
                }
            case .export:
                Section("Export Results") {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(Array(rows.chunked(into: 4).enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(row, id: \.0) { label, value in
                                    StatCard(
                                        title: label,
                                        value: value,
                                        valueColor: label == "Errors" && value > 0 ? .red : .primary
                                    )
                                }
                            }
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
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(valueColor)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
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
