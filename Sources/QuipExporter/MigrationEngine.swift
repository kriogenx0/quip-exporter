import Foundation

func run(
    client: QuipClient,
    destination: ExportDestination,
    deleteAfterCopy: Bool,
    notesAccount: String,
    markdownOutputDir: URL?,
    htmlOutputDir: URL?,
    blobCache: URL,
    confirm: ((String, [String]) async -> ExportDestination?)? = nil,
    log: (String, LogEntry.Level) async -> Void
) async {
    await log("Fetching current user...", .info)

    let user: QuipCurrentUserResponse
    do { user = try await client.getCurrentUser() } catch {
        await log("Auth failed: \(error.localizedDescription)", .error); return
    }
    await log("Authenticated as: \(user.name)", .info)

    let trashFolderId = user.trashFolderId ?? ""
    let rootIds = ([user.desktopFolderId, user.starredFolderId].compactMap { $0 }
                   + (user.sharedFolderIds ?? []))

    let notesWriter = (destination == .appleNotes || destination == .ask)
        ? NotesWriter(account: notesAccount) : nil
    let markdownWriter = (destination == .markdown || destination == .ask)
        ? markdownOutputDir.map { MarkdownWriter(outputDir: $0) } : nil
    let htmlWriter = (destination == .html || destination == .ask)
        ? htmlOutputDir.map { HTMLWriter(outputDir: $0) } : nil

    if let nw = notesWriter {
        do { _ = try nw.getOrCreateFolder(path: ["From Quip"]) } catch {
            await log("Failed to create root Notes folder: \(error.localizedDescription)", .error); return
        }
    }
    if let md = markdownWriter {
        do {
            try FileManager.default.createDirectory(at: md.outputDir.appendingPathComponent("From Quip"),
                                                    withIntermediateDirectories: true)
        } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error); return
        }
    }
    if let hw = htmlWriter {
        do {
            try FileManager.default.createDirectory(at: hw.outputDir.appendingPathComponent("From Quip"),
                                                    withIntermediateDirectories: true)
        } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error); return
        }
    }

    var visitedFolders = Set<String>()
    var visitedThreads = Set<String>()

    for fid in rootIds {
        if Task.isCancelled { break }
        await migrateFolder(
            folderId: fid, notesPath: ["From Quip"], mdPath: ["From Quip"],
            client: client, notesWriter: notesWriter, markdownWriter: markdownWriter, htmlWriter: htmlWriter,
            blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
            currentUserId: user.id, trashFolderId: trashFolderId,
            visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
            confirm: confirm, log: log
        )
    }

    await log("Done. Migrated \(visitedThreads.count) documents across \(visitedFolders.count) folders.", .info)
}

// MARK: - Folder & thread traversal

private let skippedInNotes: Set<String> = ["Desktop", "Starred", "Private"]

private func migrateFolder(
    folderId: String,
    notesPath: [String],
    mdPath: [String],
    client: QuipClient,
    notesWriter: NotesWriter?,
    markdownWriter: MarkdownWriter?,
    htmlWriter: HTMLWriter?,
    blobCache: URL,
    deleteAfterCopy: Bool,
    currentUserId: String,
    trashFolderId: String,
    visitedFolders: inout Set<String>,
    visitedThreads: inout Set<String>,
    confirm: ((String, [String]) async -> ExportDestination?)?,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visitedFolders.contains(folderId), !Task.isCancelled else { return }
    visitedFolders.insert(folderId)

    let data: QuipFolderResponse
    do { data = try await client.getFolder(folderId) } catch {
        await log("Failed to fetch folder \(folderId): \(error.localizedDescription)", .error); return
    }

    let folderTitle = data.folder.title
    let nextMdPath = mdPath + [folderTitle]
    let nextNotesPath = (notesWriter != nil && skippedInNotes.contains(folderTitle))
        ? notesPath
        : notesPath + [folderTitle]

    await log("Folder: \(nextMdPath.joined(separator: " / "))", .info)

    var notesFolderId: String? = nil
    var markdownDir: URL? = nil
    var htmlDir: URL? = nil

    if let nw = notesWriter {
        do { notesFolderId = try nw.getOrCreateFolder(path: nextNotesPath) } catch {
            await log("Failed to create Notes folder: \(error.localizedDescription)", .error); return
        }
    }
    if let mw = markdownWriter {
        do { markdownDir = try mw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error); return
        }
    }
    if let hw = htmlWriter {
        do { htmlDir = try hw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error); return
        }
    }

    for child in data.children {
        if Task.isCancelled { break }
        if let threadId = child.threadId {
            await migrateThread(
                threadId: threadId, notesPath: nextMdPath,
                notesFolderId: notesFolderId, markdownDir: markdownDir, htmlDir: htmlDir,
                client: client, notesWriter: notesWriter, markdownWriter: markdownWriter, htmlWriter: htmlWriter,
                blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, trashFolderId: trashFolderId,
                visited: &visitedThreads, confirm: confirm, log: log
            )
        } else if let childId = child.folderId {
            await migrateFolder(
                folderId: childId, notesPath: nextNotesPath, mdPath: nextMdPath,
                client: client, notesWriter: notesWriter, markdownWriter: markdownWriter, htmlWriter: htmlWriter,
                blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, trashFolderId: trashFolderId,
                visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
                confirm: confirm, log: log
            )
        }
    }
}

private func migrateThread(
    threadId: String,
    notesPath: [String],
    notesFolderId: String?,
    markdownDir: URL?,
    htmlDir: URL?,
    client: QuipClient,
    notesWriter: NotesWriter?,
    markdownWriter: MarkdownWriter?,
    htmlWriter: HTMLWriter?,
    blobCache: URL,
    deleteAfterCopy: Bool,
    currentUserId: String,
    trashFolderId: String,
    visited: inout Set<String>,
    confirm: ((String, [String]) async -> ExportDestination?)?,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visited.contains(threadId), !Task.isCancelled else { return }
    visited.insert(threadId)

    let data: QuipThreadResponse
    do { data = try await client.getThread(threadId) } catch {
        await log("Failed to fetch thread \(threadId): \(error.localizedDescription)", .error); return
    }

    let thread = data.thread
    let title = thread.title
    let rawHtml = data.html ?? ""
    let quipLink = thread.link ?? ""

    let createdStr: String
    if let usec = thread.createdUsec {
        let date = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
        createdStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    } else {
        createdStr = "Unknown"
    }

    let shared = isShared(thread: thread, currentUserId: currentUserId)
    let noteTitle = shared ? title : "\(title) (Private)"

    // In Ask mode, confirm returns which destination to use (nil = skip).
    let chosenDest: ExportDestination?
    if let confirm {
        chosenDest = await confirm(title, notesPath)
        guard chosenDest != nil, !Task.isCancelled else { return }
    } else {
        chosenDest = nil
    }

    // --- Apple Notes path ---
    if let nw = notesWriter, let folderId = notesFolderId,
       (chosenDest == nil || chosenDest == .appleNotes) {
        var html = await inlineImages(html: rawHtml, threadId: threadId, client: client, blobCache: blobCache, log: log)
        html = stripLeadingHeading(html: html, title: title)
        let folderDisplay = notesPath.dropFirst().joined(separator: " / ")
        let fullHtml = nw.buildHTML(html: html, noteTitle: noteTitle, createdStr: createdStr,
                                    folderDisplay: folderDisplay, quipLink: quipLink)

        do {
            if chosenDest == nil, try nw.noteExists(title: noteTitle, folderId: folderId, createdStr: createdStr) {
                await log("  [skipped]  \(noteTitle)", .info); return
            }
            try nw.createNote(title: noteTitle, htmlBody: fullHtml, folderId: folderId)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error); return
        }

        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                let trashedTitle = "\(noteTitle) (Trashed in Quip)"
                try nw.renameNote(oldTitle: noteTitle, newTitle: trashedTitle, folderId: folderId)
                await log("  [copied + trashed]  \(noteTitle)  (created \(createdStr))", .info)
            } catch {
                await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
            }
        } else {
            await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- Markdown path ---
    if let mw = markdownWriter, let dir = markdownDir,
       (chosenDest == nil || chosenDest == .markdown) {
        if chosenDest == nil && mw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr) {
            await log("  [skipped]  \(noteTitle)", .info); return
        }

        let resolvedHtml = await resolveImagesForMarkdown(
            html: rawHtml, threadId: threadId, client: client,
            blobCache: blobCache, dir: dir, markdownWriter: mw, log: log
        )
        let processedHtml = stripLeadingHeading(html: resolvedHtml, title: title)

        do {
            try mw.writeNote(title: noteTitle, html: processedHtml, dir: dir,
                             quipLink: quipLink, createdStr: createdStr, folderPath: notesPath)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error); return
        }

        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [copied + trashed]  \(noteTitle)  (created \(createdStr))", .info)
            } catch {
                await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
            }
        } else {
            await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- HTML path ---
    if let hw = htmlWriter, let dir = htmlDir,
       (chosenDest == nil || chosenDest == .html) {
        if chosenDest == nil && hw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr) {
            await log("  [skipped]  \(noteTitle)", .info); return
        }

        let resolvedHtml = await resolveImagesForHTML(
            html: rawHtml, threadId: threadId, client: client,
            blobCache: blobCache, dir: dir, htmlWriter: hw, log: log
        )
        let processedHtml = stripLeadingHeading(html: resolvedHtml, title: title)

        do {
            try hw.writeNote(title: noteTitle, html: processedHtml, dir: dir,
                             quipLink: quipLink, createdStr: createdStr, folderPath: notesPath)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error); return
        }

        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [copied + trashed]  \(noteTitle)  (created \(createdStr))", .info)
            } catch {
                await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
            }
        } else {
            await log("  [copied]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }
}

// MARK: - Helpers

private func isShared(thread: QuipThreadInfo, currentUserId: String) -> Bool {
    guard let members = thread.memberIds, !members.isEmpty else { return true }
    if members.contains(where: { $0 != currentUserId }) { return true }
    if let mode = thread.sharing?.companyMode, mode != "NONE" { return true }
    return false
}

private func stripLeadingHeading(html: String, title: String) -> String {
    let pattern = #"^\s*<h[1-6][^>]*>(.*?)</h[1-6]>\s*"#
    guard let regex = try? NSRegularExpression(pattern: pattern,
                                               options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return html }
    let ns = html as NSString
    guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
          let innerRange = Range(match.range(at: 1), in: html) else { return html }
    let headingText = String(html[innerRange])
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard headingText.lowercased() == title.lowercased(),
          let fullRange = Range(match.range, in: html) else { return html }
    return String(html[fullRange.upperBound...])
}

private func fetchBlob(threadId: String, blobHash: String, client: QuipClient, blobCache: URL) async throws -> Data {
    let cacheFile = blobCache.appendingPathComponent(threadId).appendingPathComponent(blobHash)
    if let cached = try? Data(contentsOf: cacheFile) { return cached }
    let data = try await client.getBlob(threadId: threadId, blobHash: blobHash)
    try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: cacheFile)
    return data
}

private func replaceBlobSrcs(
    in html: String,
    client: QuipClient,
    blobCache: URL,
    log: (String, LogEntry.Level) async -> Void,
    makeSrc: (Data, String) throws -> String
) async -> String {
    let pattern = #"src="(?:https://platform\.quip(?:-apple)?\.com/1)?/blob/([A-Za-z0-9]+)/([A-Za-z0-9]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
    let ns = html as NSString
    let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
    var replacements: [(NSRange, String)] = []

    for match in matches {
        guard !Task.isCancelled else { break }
        let tid = ns.substring(with: match.range(at: 1))
        let hash = ns.substring(with: match.range(at: 2))
        do {
            let data = try await fetchBlob(threadId: tid, blobHash: hash, client: client, blobCache: blobCache)
            replacements.append((match.range, "src=\"\(try makeSrc(data, hash))\""))
        } catch {
            await log("Could not fetch blob \(hash): \(error.localizedDescription)", .warning)
        }
    }

    let result = NSMutableString(string: html)
    for (range, replacement) in replacements.reversed() {
        result.replaceCharacters(in: range, with: replacement)
    }
    return result as String
}

private func inlineImages(
    html: String, threadId: String, client: QuipClient, blobCache: URL,
    log: (String, LogEntry.Level) async -> Void
) async -> String {
    await replaceBlobSrcs(in: html, client: client, blobCache: blobCache, log: log) { data, _ in
        let mime = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

private func resolveImagesForMarkdown(
    html: String, threadId: String, client: QuipClient, blobCache: URL,
    dir: URL, markdownWriter: MarkdownWriter,
    log: (String, LogEntry.Level) async -> Void
) async -> String {
    await replaceBlobSrcs(in: html, client: client, blobCache: blobCache, log: log) { data, hash in
        try markdownWriter.saveImage(data: data, blobHash: hash, dir: dir)
    }
}

private func resolveImagesForHTML(
    html: String, threadId: String, client: QuipClient, blobCache: URL,
    dir: URL, htmlWriter: HTMLWriter,
    log: (String, LogEntry.Level) async -> Void
) async -> String {
    await replaceBlobSrcs(in: html, client: client, blobCache: blobCache, log: log) { data, hash in
        try htmlWriter.saveImage(data: data, blobHash: hash, dir: dir)
    }
}
