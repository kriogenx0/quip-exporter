import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let level: Level

    enum Level { case info, warning, error }
}

enum ExportDestination: String, CaseIterable, Identifiable {
    case appleNotes = "Apple Notes"
    case numbers = "Numbers"
    case csv = "CSV"
    case markdown = "Markdown Files"
    case html = "HTML Files"
    case ask = "Ask"
    var id: String { rawValue }
}

enum QuipDomain: String, CaseIterable, Identifiable {
    case quipApple = "quip-apple.com"
    case quip = "quip.com"
    var id: String { rawValue }
    var baseURL: URL { URL(string: "https://platform.\(rawValue)/1")! }
    var tokenURL: URL { URL(string: "https://\(rawValue)/dev/token")! }
}

// The user's response when a document/spreadsheet already exists in the destination.
enum OverwriteChoice {
    case overwrite, skip, stop
}

// How to handle a document/spreadsheet that already exists in the destination and
// differs from the Quip version — set once in Settings instead of per-item.
enum ExistingFileBehavior: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case overwrite = "Overwrite"
    case ignore = "Ignore"
    var id: String { rawValue }
}

// Result of manually re-checking a token via the "Test Token" button.
struct TokenTestResult {
    let succeeded: Bool
    let message: String
}

// Outcome of a single file/note write attempt, for display in the Files tab.
enum FileStatus: Equatable {
    case copied, skipped, error
}

// A single file (or Apple Notes note) touched during a real export run, for display in
// the Files tab.
struct CopiedFile: Identifiable, Equatable {
    let id = UUID()
    let directory: String
    let file: String
    let status: FileStatus
}

// Tallies produced by a read-only scan of the Quip account, without writing anything.
struct ScanSummary: Equatable {
    var toTransfer = 0
    var toUpdate = 0
    var toTrash = 0
}

// Tallies produced by a real run(), updated live via the `count` callback as each
// folder/document is processed.
struct RunSummary {
    var foldersVisited = 0
    var documentsTransferred = 0
    var documentsUpdated = 0
    var documentsUnchanged = 0
    var documentsSkipped = 0
    var documentsTrashed = 0
    var errors = 0
}

enum RunEvent {
    case folder, transferred, updated, unchanged, skipped, trashed, error
}

// Which results the Summary tab should display — whichever action (scan or export)
// ran most recently, so the tab keeps showing that data during the run and after it finishes.
enum ResultsKind {
    case none, scan, export
}

// Stops a run/scan the moment anything goes wrong — an auth rejection, a failed
// fetch, a write failure — rather than limping on and reporting a pile of per-item
// errors at the end. isAuthFailure distinguishes a rejected token (which prompts for
// a new one) from any other error (which just needs to be surfaced and stop the run).
final class RunGuard {
    private(set) var stopped = false
    private(set) var failureReason: String?
    private(set) var isAuthFailure = false

    func stop(reason: String, isAuthFailure: Bool = false) {
        guard !stopped else { return }
        stopped = true
        failureReason = reason
        self.isAuthFailure = isAuthFailure
    }
}

// MARK: - Quip API models

struct QuipCurrentUserResponse: Decodable {
    let id: String
    let name: String
    let desktopFolderId: String?
    let starredFolderId: String?
    let sharedFolderIds: [String]?
    let trashFolderId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case desktopFolderId = "desktop_folder_id"
        case starredFolderId = "starred_folder_id"
        case sharedFolderIds = "shared_folder_ids"
        case trashFolderId = "trash_folder_id"
    }
}

struct QuipFolderResponse: Decodable {
    let folder: QuipFolderInfo
    let children: [QuipFolderChild]
}

struct QuipFolderInfo: Decodable {
    let id: String
    let title: String
}

struct QuipFolderChild: Decodable {
    let threadId: String?
    let folderId: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case folderId = "folder_id"
    }
}

struct QuipThreadResponse: Decodable {
    let thread: QuipThreadInfo
    let html: String?
}

struct QuipThreadInfo: Decodable {
    let id: String
    let title: String
    let link: String?
    let createdUsec: Int64?
    let memberIds: [String]?
    let sharing: QuipSharing?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, title, link, sharing, type
        case createdUsec = "created_usec"
        case memberIds = "member_ids"
    }

    // Quip's documented thread types are document/spreadsheet/slides/chat.
    // Unrecognized or missing values fall back to non-spreadsheet handling.
    var isSpreadsheet: Bool { type == "spreadsheet" }
}

struct QuipSharing: Decodable {
    let companyMode: String?
    enum CodingKeys: String, CodingKey { case companyMode = "company_mode" }
}

// MARK: - Errors

enum MigrationError: Error, LocalizedError {
    case api(statusCode: Int, path: String, body: String)
    // Either Quip's own signal that the access token is invalid/expired/revoked, or a
    // 403 "Not authorized" on a specific folder/thread — both stop the run and prompt
    // the user, since either way nothing more can be fetched with this token/access.
    case notAuthorized(path: String, body: String)

    var errorDescription: String? {
        switch self {
        case .api(let code, let path, let body):
            return "Quip API \(code) for \(path): \(body)"
        case .notAuthorized(let path, let body):
            return "Not authorized for \(path): \(body)"
        }
    }
}

func isAuthError(_ error: Error) -> Bool {
    if case MigrationError.notAuthorized = error { return true }
    return false
}

enum NotesError: Error, LocalizedError {
    case applescript(String)

    var errorDescription: String? {
        if case .applescript(let msg) = self { return "AppleScript: \(msg)" }
        return nil
    }
}

enum SpreadsheetError: Error, LocalizedError {
    case noTablesFound
    case fileNotWritten(path: String)

    var errorDescription: String? {
        switch self {
        case .noTablesFound: return "No tables found in the spreadsheet HTML"
        case .fileNotWritten(let path):
            return "Numbers reported success but didn't write \(path) — the save may have been interrupted (e.g. by a dialog it couldn't dismiss on its own)."
        }
    }
}
