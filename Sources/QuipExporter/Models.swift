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

// Watches for repeated 401/403 responses while a run/scan is in progress. A single
// 403 can just mean one item lost its sharing permissions, but a 401 (token flatly
// rejected) or several 403s in a row almost always means the token expired or was
// revoked mid-run — in which case every remaining folder/thread fetch would otherwise
// fail the same way, so we stop instead of grinding through the rest of the account.
final class AuthGuard {
    private(set) var stopped = false
    private var consecutiveFailures = 0

    // Returns true the moment this failure trips the stop condition.
    func recordFailure(statusCode: Int) -> Bool {
        guard statusCode == 401 || statusCode == 403 else { return false }
        if statusCode == 401 {
            stopped = true
            return true
        }
        consecutiveFailures += 1
        if consecutiveFailures >= 2 {
            stopped = true
            return true
        }
        return false
    }

    func recordSuccess() {
        consecutiveFailures = 0
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

    var errorDescription: String? {
        switch self {
        case .api(let code, let path, let body):
            return "Quip API \(code) for \(path): \(body)"
        }
    }
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

    var errorDescription: String? {
        switch self {
        case .noTablesFound: return "No tables found in the spreadsheet HTML"
        }
    }
}
