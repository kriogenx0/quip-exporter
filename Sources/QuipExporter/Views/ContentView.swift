import SwiftUI

struct ContentView: View {
    @AppStorage("quipToken") private var quipToken = ""
    @AppStorage("quipDomain") private var quipDomain: QuipDomain = .quipApple
    @AppStorage("destination") private var destination: ExportDestination = .appleNotes
    @AppStorage("deleteAfterCopy") private var deleteAfterCopy = false
    @AppStorage("notesAccount") private var notesAccount = ""
    @State private var markdownOutputDir: URL? = nil
    @State private var htmlOutputDir: URL? = nil

    @StateObject private var runner = MigrationRunner()

    var body: some View {
        VStack(spacing: 0) {
            SettingsPanel(
                quipToken: $quipToken,
                quipDomain: $quipDomain,
                destination: $destination,
                deleteAfterCopy: $deleteAfterCopy,
                notesAccount: $notesAccount,
                markdownOutputDir: $markdownOutputDir,
                htmlOutputDir: $htmlOutputDir,
                isRunning: runner.isRunning
            )
            .fixedSize(horizontal: false, vertical: true)

            MigrationInfoBanner(destination: destination, deleteAfterCopy: deleteAfterCopy,
                                notesAccount: notesAccount, markdownOutputDir: markdownOutputDir,
                                htmlOutputDir: htmlOutputDir)

            Divider()

            LogPanel(entries: runner.logEntries)

            Divider()

            ControlBar(
                runner: runner,
                quipToken: quipToken,
                quipDomain: quipDomain,
                destination: destination,
                deleteAfterCopy: deleteAfterCopy,
                notesAccount: notesAccount,
                markdownOutputDir: markdownOutputDir,
                htmlOutputDir: htmlOutputDir
            )
        }
        .frame(minWidth: 650, minHeight: 550)
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @Binding var quipToken: String
    @Binding var quipDomain: QuipDomain
    @Binding var destination: ExportDestination
    @Binding var deleteAfterCopy: Bool
    @Binding var notesAccount: String
    @Binding var markdownOutputDir: URL?
    @Binding var htmlOutputDir: URL?
    let isRunning: Bool
    @State private var showToken = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Quip Token").font(.headline)
                    Spacer()
                    Link("Get token", destination: quipDomain.tokenURL)
                        .font(.body)
                }

                HStack {

                    TokenField(text: $quipToken, isSecure: !showToken)
                        .frame(height: 22)

                    Button { showToken.toggle() } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                }

                HStack {
                    Text("Platform")
                    Spacer()
                    Picker("", selection: $quipDomain) {
                        ForEach(QuipDomain.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            Section {
                HStack {
                    Text("Export to")
                    Spacer()
                    Picker("", selection: $destination) {
                        ForEach(ExportDestination.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if destination == .markdown || destination == .html {
                    LabeledContent("Output Folder") {
                        HStack {
                            let dir = destination == .markdown ? markdownOutputDir : htmlOutputDir
                            Text(dir?.path ?? "Not selected")
                                .foregroundStyle(dir == nil ? .secondary : .primary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK {
                                    if destination == .markdown { markdownOutputDir = panel.url }
                                    else { htmlOutputDir = panel.url }
                                }
                            }
                        }
                    }
                }

                if destination == .ask {
                    LabeledContent("Markdown Folder") {
                        HStack {
                            Text(markdownOutputDir?.path ?? "Not configured")
                                .foregroundStyle(markdownOutputDir == nil ? .secondary : .primary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button(markdownOutputDir == nil ? "Configure…" : "Change…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK { markdownOutputDir = panel.url }
                            }
                        }
                    }
                    LabeledContent("HTML Folder") {
                        HStack {
                            Text(htmlOutputDir?.path ?? "Not configured")
                                .foregroundStyle(htmlOutputDir == nil ? .secondary : .primary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Button(htmlOutputDir == nil ? "Configure…" : "Change…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK { htmlOutputDir = panel.url }
                            }
                        }
                    }
                }

                Toggle("Delete private Quip documents after copying", isOn: $deleteAfterCopy)
            }
        }
        .formStyle(.grouped)
        .disabled(isRunning)
        .padding(.horizontal, 4)
    }
}

// MARK: - Migration info banner

struct MigrationInfoBanner: View {
    let destination: ExportDestination
    let deleteAfterCopy: Bool
    let notesAccount: String
    let markdownOutputDir: URL?
    let htmlOutputDir: URL?

    private var description: String {
        var parts: [String] = []

        switch destination {
        case .appleNotes:
            let account = notesAccount.isEmpty ? "your default Notes account" : "the \"\(notesAccount)\" account"
            parts.append("Copies documents from your Quip account (Desktop, Starred, and Shared folders) into \(account) under a top-level \"From Quip\" folder, preserving the folder hierarchy. Desktop, Starred, and Private folders are flattened into the root.")
        case .markdown:
            let folder = markdownOutputDir.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
            parts.append("Exports documents from your Quip account (Desktop, Starred, and Shared folders) as Markdown files inside \(folder), preserving the folder hierarchy. Images are saved alongside each file in an _assets/ subfolder.")
        case .html:
            let folder = htmlOutputDir.map { "\"\($0.lastPathComponent)\"" } ?? "the selected folder"
            parts.append("Exports documents from your Quip account (Desktop, Starred, and Shared folders) as HTML files inside \(folder), preserving the folder hierarchy. Images are saved alongside each file in an _assets/ subfolder.")
        case .ask:
            parts.append("For each document, asks where to export it: Apple Notes, Markdown, or HTML. Configure the Markdown and HTML folders above to enable those options in the dialog.")
        }

        if deleteAfterCopy {
            parts.append("Private (unshared) documents will be moved to Quip Trash after copying.")
        }

        if destination != .ask {
            parts.append("Already-exported documents are skipped on re-runs.")
        }

        return parts.joined(separator: " ")
    }

    var body: some View {
        Text(description)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
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
    let destination: ExportDestination
    let deleteAfterCopy: Bool
    let notesAccount: String
    let markdownOutputDir: URL?
    let htmlOutputDir: URL?

    private var canStart: Bool {
        guard !quipToken.isEmpty else { return false }
        if destination == .markdown { return markdownOutputDir != nil }
        if destination == .html { return htmlOutputDir != nil }
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
                }
                if !runner.isRunning && destination == .appleNotes {
                    Button("Create Test Note") {
                        runner.runFormattingTest(notesAccount: notesAccount)
                    }
                }
            }

            // Button centered independently
            if runner.isRunning {
                Button("Stop", role: .destructive) { runner.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button {
                    runner.start(
                        token: quipToken,
                        domain: quipDomain,
                        destination: destination,
                        deleteAfterCopy: deleteAfterCopy,
                        rateDelay: 0.5,
                        notesAccount: notesAccount,
                        markdownOutputDir: markdownOutputDir,
                        htmlOutputDir: htmlOutputDir
                    )
                } label: {
                    Label("Start Exporting", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
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
