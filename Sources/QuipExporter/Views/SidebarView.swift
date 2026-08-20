import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var quipToken: String
    @Binding var quipDomain: QuipDomain
    @Binding var documentDestination: ExportDestination
    @Binding var spreadsheetDestination: ExportDestination
    @Binding var deleteAfterCopy: Bool
    @Binding var existingFileBehavior: ExistingFileBehavior
    let notesAccount: String
    @Binding var exportFolder: URL?
    let isRunning: Bool
    let canStart: Bool
    let tokenTestResult: TokenTestResult?
    let onTestToken: () -> Void
    let onScan: () -> Void
    let onExport: () -> Void
    let onStop: () -> Void

    @State private var showToken = false
    @State private var showDescription = false

    private var needsExportFolder: Bool {
        documentDestination != .appleNotes || spreadsheetDestination != .appleNotes
    }

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            actionBar
        }
    }

    private var form: some View {
        Form {
            Section("Account") {
                Picker("Domain", selection: $quipDomain) {
                    ForEach(QuipDomain.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }

                LabeledContent("Token") {
                    HStack(spacing: 6) {
                        TokenField(text: $quipToken, isSecure: !showToken)
                            .frame(height: 22)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                            )

                        Button {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                quipToken = pasted
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button { showToken.toggle() } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Get Token…") {
                        NSWorkspace.shared.open(quipDomain.tokenURL)
                    }
                    Spacer()
                    Button("Test Token") { onTestToken() }
                }

                if let tokenTestResult {
                    Label(tokenTestResult.message, systemImage: tokenTestResult.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(tokenTestResult.succeeded ? .green : .red)
                        .font(.callout)
                }
            }
            .disabled(isRunning)

            Section("Export") {
                Picker("Documents", selection: $documentDestination) {
                    ForEach(ExportDestination.allCases.filter { $0 != .numbers && $0 != .csv }) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                Picker("Spreadsheets", selection: $spreadsheetDestination) {
                    ForEach(ExportDestination.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }

                if needsExportFolder {
                    FolderPickerRow(url: $exportFolder)
                }

                Picker("If file exists", selection: $existingFileBehavior) {
                    ForEach(ExistingFileBehavior.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }

                Toggle("Delete private documents after copying", isOn: $deleteAfterCopy)
            }
            .disabled(isRunning)

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    DisclosureHeader(title: "What does this do?", isExpanded: $showDescription)

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
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: isRunning) { newValue in
            if newValue { showDescription = false }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if isRunning {
                Button("Stop", role: .destructive) { onStop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(maxWidth: .infinity)
            } else {
                if !quipToken.isEmpty {
                    Button {
                        onScan()
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
        .padding(12)
    }
}

private struct DisclosureHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.secondary.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct FolderPickerRow: View {
    @Binding var url: URL?

    var body: some View {
        LabeledContent("Folder") {
            VStack(alignment: .trailing, spacing: 4) {
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

// MARK: - Migration description

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
