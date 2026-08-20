import SwiftUI
import AppKit

struct DetailView: View {
    @ObservedObject var runner: MigrationRunner
    let quipDomain: QuipDomain
    @State private var showLogs = false

    var body: some View {
        VStack(spacing: 0) {
            if runner.isRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(runner.resultsKind == .scan ? "Scanning…" : "Exporting…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }

            SummaryView(
                resultsKind: runner.resultsKind,
                summary: runner.runSummary,
                scanSummary: runner.scanSummary,
                authError: runner.authError,
                files: runner.copiedFiles,
                scannedDocuments: runner.scannedDocuments,
                quipDomain: quipDomain
            )
            .frame(maxHeight: .infinity)

            Divider()

            LogsDisclosure(entries: runner.logEntries, isExpanded: $showLogs)
        }
    }
}

// MARK: - Summary (stats + copied files)

struct SummaryView: View {
    let resultsKind: ResultsKind
    let summary: RunSummary
    let scanSummary: ScanSummary?
    let authError: String?
    let files: [CopiedFile]
    let scannedDocuments: [ScannedDocument]
    let quipDomain: QuipDomain

    private var statRows: [(String, Int, Bool)] {
        [
            ("Folders found", summary.foldersVisited, false),
            ("Transferred", summary.documentsTransferred, false),
            ("Updated", summary.documentsUpdated, false),
            ("Unchanged", summary.documentsUnchanged, false),
            ("Skipped", summary.documentsSkipped, false),
            ("Trashed in Quip", summary.documentsTrashed, false),
            ("Errors", summary.errors, true),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let authError {
                ErrorBanner(message: authError, quipDomain: quipDomain)
                    .padding([.horizontal, .top], 16)
            }

            switch resultsKind {
            case .none:
                emptyState
            case .scan:
                VStack(alignment: .leading, spacing: 20) {
                    StatGrid(items: [
                        ("To transfer", scanSummary?.toTransfer ?? 0, false),
                        ("To update", scanSummary?.toUpdate ?? 0, false),
                        ("To trash after copying", scanSummary?.toTrash ?? 0, false),
                    ])
                    .padding([.horizontal, .top], 16)

                    if !scannedDocuments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Documents")
                                .font(.headline)
                                .padding(.horizontal, 16)
                            ScannedDocumentsList(documents: scannedDocuments)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer()
                    }
                }
            case .export:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StatGrid(items: statRows)

                        if !files.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Files")
                                    .font(.headline)
                                FilesList(files: files)
                                    .frame(minHeight: 200, maxHeight: .infinity)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Run a scan or start an export to see results.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorBanner: View {
    let message: String
    let quipDomain: QuipDomain

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .foregroundStyle(.primary)
                if message.contains("Invalid access_token") {
                    Button("Get Token…") {
                        NSWorkspace.shared.open(quipDomain.tokenURL)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }
}

private struct StatGrid: View {
    let items: [(String, Int, Bool)]

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { label, value, isError in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(isError && value > 0 ? .red : .primary)
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }
}

// MARK: - Files

private struct FilesList: View {
    let files: [CopiedFile]

    var body: some View {
        List(files) { file in
            HStack(alignment: .top, spacing: 8) {
                FileStatusIcon(status: file.status)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.directory)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(file.file)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct FileStatusIcon: View {
    let status: FileStatus

    var body: some View {
        switch status {
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Scanned documents (grouped by parent directory)

private struct ScannedDocumentsList: View {
    let documents: [ScannedDocument]

    private var groups: [(directory: String, documents: [ScannedDocument])] {
        var order: [String] = []
        var byDirectory: [String: [ScannedDocument]] = [:]
        for doc in documents {
            if byDirectory[doc.directory] == nil { order.append(doc.directory) }
            byDirectory[doc.directory, default: []].append(doc)
        }
        return order.map { ($0, byDirectory[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.directory) { group in
                Section(group.directory) {
                    ForEach(group.documents) { doc in
                        Text(doc.title)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding([.horizontal, .bottom], 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Logs

private struct LogsDisclosure: View {
    let entries: [LogEntry]
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Logs")
                        .font(.headline)
                    if !entries.isEmpty {
                        Text("\(entries.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if isExpanded {
                Divider()
                LogPanel(entries: entries)
                    .frame(height: 220)
            }
        }
    }
}

struct LogPanel: View {
    let entries: [LogEntry]

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No log entries yet")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LogView(entries: entries)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
