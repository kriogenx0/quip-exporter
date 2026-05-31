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
    case markdown = "Markdown Files"
    case html = "HTML Files"
    var id: String { rawValue }
}

enum QuipDomain: String, CaseIterable, Identifiable {
    case quipApple = "quip-apple.com"
    case quip = "quip.com"
    var id: String { rawValue }
    var baseURL: URL { URL(string: "https://platform.\(rawValue)/1")! }
    var tokenURL: URL { URL(string: "https://\(rawValue)/dev/token")! }
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

    enum CodingKeys: String, CodingKey {
        case id, title, link, sharing
        case createdUsec = "created_usec"
        case memberIds = "member_ids"
    }
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
