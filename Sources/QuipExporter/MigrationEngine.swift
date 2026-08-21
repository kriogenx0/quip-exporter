import Foundation

private struct Writers {
    let notes: NotesWriter?
    let markdown: MarkdownWriter?
    let html: HTMLWriter?
    let numbers: NumbersWriter?
    let csv: CSVWriter?
}

private struct WriterDirs {
    var notesFolderId: String?
    var markdownDir: URL?
    var htmlDir: URL?
    var numbersDir: URL?
    var csvDir: URL?
}

private struct DestinationConfig {
    let document: ExportDestination
    let spreadsheet: ExportDestination
    let confirm: ((String, [String], Bool) async -> ExportDestination?)?
    let confirmOverwrite: ((String, [String], String?, String?) async -> OverwriteChoice)?
}

func run(
    client: QuipClient,
    documentDestination: ExportDestination,
    spreadsheetDestination: ExportDestination,
    deleteAfterCopy: Bool,
    notesAccount: String,
    exportFolder: URL?,
    blobCache: URL,
    confirm: ((String, [String], Bool) async -> ExportDestination?)? = nil,
    confirmOverwrite: ((String, [String], String?, String?) async -> OverwriteChoice)? = nil,
    notifyFailure: (String) async -> Void = { _ in },
    count: (RunEvent) async -> Void = { _ in },
    recordFile: (String, String, FileStatus) async -> Void = { _, _, _ in },
    log: (String, LogEntry.Level) async -> Void
) async {
    await log("Fetching current user...", .info)

    let user: QuipCurrentUserResponse
    do { user = try await client.getCurrentUser() } catch {
        await log("Auth failed: \(error.localizedDescription)", .error)
        if case MigrationError.notAuthorized = error { await notifyFailure(error.localizedDescription) }
        return
    }
    await log("Authenticated as: \(user.name)", .info)

    let trashFolderId = user.trashFolderId ?? ""
    let rootIds = ([user.desktopFolderId, user.starredFolderId].compactMap { $0 }
                   + (user.sharedFolderIds ?? []))

    let categories = [documentDestination, spreadsheetDestination]
    let notesWriter = (categories.contains(.appleNotes) || categories.contains(.ask))
        ? NotesWriter(account: notesAccount) : nil
    let markdownWriter = (categories.contains(.markdown) || categories.contains(.ask))
        ? exportFolder.map { MarkdownWriter(outputDir: $0) } : nil
    let htmlWriter = (categories.contains(.html) || categories.contains(.ask))
        ? exportFolder.map { HTMLWriter(outputDir: $0) } : nil
    let numbersWriter = (spreadsheetDestination == .numbers || spreadsheetDestination == .ask)
        ? exportFolder.map { NumbersWriter(outputDir: $0) } : nil
    let csvWriter = (spreadsheetDestination == .csv || spreadsheetDestination == .ask)
        ? exportFolder.map { CSVWriter(outputDir: $0) } : nil
    let writers = Writers(notes: notesWriter, markdown: markdownWriter, html: htmlWriter, numbers: numbersWriter, csv: csvWriter)
    let destinations = DestinationConfig(document: documentDestination, spreadsheet: spreadsheetDestination,
                                          confirm: confirm, confirmOverwrite: confirmOverwrite)

    if let nw = writers.notes {
        do { _ = try nw.getOrCreateFolder(path: ["Quip Export"]) } catch {
            await log("Failed to create root Notes folder: \(error.localizedDescription)", .error); return
        }
    }

    var visitedFolders = Set<String>()
    var visitedThreads = Set<String>()
    let runGuard = RunGuard()

    for fid in rootIds {
        if Task.isCancelled || runGuard.stopped { break }
        await migrateFolder(
            folderId: fid, notesPath: ["Quip Export"], mdPath: ["Quip Export"],
            client: client, writers: writers,
            blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
            currentUserId: user.id, trashFolderId: trashFolderId,
            visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
            destinations: destinations, runGuard: runGuard, count: count, recordFile: recordFile, log: log
        )
    }

    if runGuard.stopped {
        if runGuard.isAuthFailure {
            await log("Stopped: the Quip token was rejected (expired or revoked).", .error)
        } else {
            await log("Stopped: \(runGuard.failureReason ?? "an error occurred").", .error)
        }
        await notifyFailure(runGuard.failureReason ?? "The Quip token was rejected.")
    } else {
        await log("Done. Migrated \(visitedThreads.count) documents across \(visitedFolders.count) folders.", .info)
    }
}

// Read-only pass over the whole account: fetches the same folders/threads as run(...)
// but never writes anything, tallying what a real run would transfer, update, or trash.
func scan(
    client: QuipClient,
    documentDestination: ExportDestination,
    spreadsheetDestination: ExportDestination,
    deleteAfterCopy: Bool,
    notesAccount: String,
    exportFolder: URL?,
    notifyFailure: (String) async -> Void = { _ in },
    count: (ScanEvent) async -> Void = { _ in },
    recordFile: (String, String, FileStatus) async -> Void = { _, _, _ in },
    log: (String, LogEntry.Level) async -> Void
) async -> ScanSummary? {
    await log("Scanning Quip account...", .info)

    let user: QuipCurrentUserResponse
    do { user = try await client.getCurrentUser() } catch {
        await log("Auth failed: \(error.localizedDescription)", .error)
        if case MigrationError.notAuthorized = error { await notifyFailure(error.localizedDescription) }
        return nil
    }
    await log("Authenticated as: \(user.name)", .info)

    let rootIds = ([user.desktopFolderId, user.starredFolderId].compactMap { $0 }
                   + (user.sharedFolderIds ?? []))

    let categories = [documentDestination, spreadsheetDestination]
    let notesWriter = (categories.contains(.appleNotes) || categories.contains(.ask))
        ? NotesWriter(account: notesAccount) : nil
    let markdownWriter = (categories.contains(.markdown) || categories.contains(.ask))
        ? exportFolder.map { MarkdownWriter(outputDir: $0) } : nil
    let htmlWriter = (categories.contains(.html) || categories.contains(.ask))
        ? exportFolder.map { HTMLWriter(outputDir: $0) } : nil
    let numbersWriter = (spreadsheetDestination == .numbers || spreadsheetDestination == .ask)
        ? exportFolder.map { NumbersWriter(outputDir: $0) } : nil
    let csvWriter = (spreadsheetDestination == .csv || spreadsheetDestination == .ask)
        ? exportFolder.map { CSVWriter(outputDir: $0) } : nil
    let writers = Writers(notes: notesWriter, markdown: markdownWriter, html: htmlWriter, numbers: numbersWriter, csv: csvWriter)
    let destinations = DestinationConfig(document: documentDestination, spreadsheet: spreadsheetDestination,
                                          confirm: nil, confirmOverwrite: nil)

    let needsFolder = documentDestination == .markdown || documentDestination == .html
        || spreadsheetDestination == .markdown || spreadsheetDestination == .html
        || spreadsheetDestination == .numbers || spreadsheetDestination == .csv
    if needsFolder && exportFolder == nil {
        await log("Documents/spreadsheets are set to a folder-based destination but no export folder is configured — those will be excluded from this scan.", .warning)
    }

    var summary = ScanSummary()
    var visitedFolders = Set<String>()
    var visitedThreads = Set<String>()
    let runGuard = RunGuard()

    for fid in rootIds {
        if Task.isCancelled || runGuard.stopped { break }
        await scanFolder(
            folderId: fid, notesPath: ["Quip Export"], mdPath: ["Quip Export"],
            client: client, writers: writers, deleteAfterCopy: deleteAfterCopy,
            currentUserId: user.id, visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
            destinations: destinations, runGuard: runGuard, summary: &summary, count: count, recordFile: recordFile, log: log
        )
    }

    if runGuard.stopped {
        if runGuard.isAuthFailure {
            await log("Scan stopped: the Quip token was rejected (expired or revoked).", .error)
        } else {
            await log("Scan stopped: \(runGuard.failureReason ?? "an error occurred").", .error)
        }
        await notifyFailure(runGuard.failureReason ?? "The Quip token was rejected.")
        return nil
    }

    await log("Scan complete. \(summary.toTransfer) to transfer, \(summary.toUpdate) to update, \(summary.toTrash) to delete (trash in Quip) after copying.", .info)
    return summary
}

// Fetches a folder level's children ahead of the sequential loop below. QuipClient is
// an actor whose per-request rate-limit delay is a Task.sleep inside get() — since
// actors are reentrant across suspension points, concurrent prefetch calls overlap
// their delays instead of paying rateDelay once per item serially, and populate the
// on-disk cache so the sequential loop just reads it back. Results/errors are
// discarded here; the real fetch (and any error handling) happens in that loop.
private func prefetchChildren(_ children: [QuipFolderChild], client: QuipClient) async {
    let maxConcurrency = 8
    await withTaskGroup(of: Void.self) { group in
        var iterator = children.makeIterator()
        func addNext() {
            guard !Task.isCancelled, let child = iterator.next() else { return }
            group.addTask {
                if let tid = child.threadId {
                    _ = try? await client.getThread(tid)
                } else if let fid = child.folderId {
                    _ = try? await client.getFolder(fid)
                }
            }
        }
        for _ in 0..<maxConcurrency { addNext() }
        while await group.next() != nil { addNext() }
    }
}

// MARK: - Folder & thread traversal

private let skippedInNotes: Set<String> = ["Desktop", "Starred", "Private"]

// Folder names that are flattened out of the file-based export path (Markdown/HTML/
// Numbers/CSV) — e.g. "Desktop / Archive / Foo" becomes "Desktop / Foo".
private let skippedInFiles: Set<String> = ["Archive"]

private func migrateFolder(
    folderId: String,
    notesPath: [String],
    mdPath: [String],
    client: QuipClient,
    writers: Writers,
    blobCache: URL,
    deleteAfterCopy: Bool,
    currentUserId: String,
    trashFolderId: String,
    visitedFolders: inout Set<String>,
    visitedThreads: inout Set<String>,
    destinations: DestinationConfig,
    runGuard: RunGuard,
    count: (RunEvent) async -> Void,
    recordFile: (String, String, FileStatus) async -> Void,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visitedFolders.contains(folderId), !Task.isCancelled, !runGuard.stopped else { return }
    visitedFolders.insert(folderId)

    let data: QuipFolderResponse
    do { data = try await client.getFolder(folderId) } catch {
        await log("Failed to fetch folder \(folderId): \(error.localizedDescription)", .error)
        await count(.error)
        runGuard.stop(reason: error.localizedDescription, isAuthFailure: isAuthError(error))
        return
    }

    let folderTitle = data.folder.title
    let nextMdPath = skippedInFiles.contains(folderTitle) ? mdPath : mdPath + [folderTitle]
    let nextNotesPath = (writers.notes != nil && skippedInNotes.contains(folderTitle))
        ? notesPath
        : notesPath + [folderTitle]

    await log("Folder: \(nextMdPath.dropFirst().joined(separator: " / "))", .info)
    await count(.folder)

    var dirs = WriterDirs()

    if let nw = writers.notes {
        do { dirs.notesFolderId = try nw.getOrCreateFolder(path: nextNotesPath) } catch {
            await log("Failed to create Notes folder: \(error.localizedDescription)", .error)
            await count(.error)
            runGuard.stop(reason: error.localizedDescription)
            return
        }
    }
    if let mw = writers.markdown {
        do { dirs.markdownDir = try mw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error)
            await count(.error)
            runGuard.stop(reason: error.localizedDescription)
            return
        }
    }
    if let hw = writers.html {
        do { dirs.htmlDir = try hw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error)
            await count(.error)
            runGuard.stop(reason: error.localizedDescription)
            return
        }
    }
    if let nuw = writers.numbers {
        do { dirs.numbersDir = try nuw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error)
            await count(.error)
            runGuard.stop(reason: error.localizedDescription)
            return
        }
    }
    if let cw = writers.csv {
        do { dirs.csvDir = try cw.ensureFolder(path: nextMdPath) } catch {
            await log("Failed to create output folder: \(error.localizedDescription)", .error)
            await count(.error)
            runGuard.stop(reason: error.localizedDescription)
            return
        }
    }

    await prefetchChildren(data.children, client: client)

    for child in data.children {
        if Task.isCancelled || runGuard.stopped { break }
        if let threadId = child.threadId {
            await migrateThread(
                threadId: threadId, notesPath: nextMdPath, dirs: dirs,
                client: client, writers: writers,
                blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, trashFolderId: trashFolderId,
                visited: &visitedThreads, destinations: destinations, runGuard: runGuard, count: count, recordFile: recordFile, log: log
            )
        } else if let childId = child.folderId {
            await migrateFolder(
                folderId: childId, notesPath: nextNotesPath, mdPath: nextMdPath,
                client: client, writers: writers,
                blobCache: blobCache, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, trashFolderId: trashFolderId,
                visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
                destinations: destinations, runGuard: runGuard, count: count, recordFile: recordFile, log: log
            )
        }
    }
}

private func migrateThread(
    threadId: String,
    notesPath: [String],
    dirs: WriterDirs,
    client: QuipClient,
    writers: Writers,
    blobCache: URL,
    deleteAfterCopy: Bool,
    currentUserId: String,
    trashFolderId: String,
    visited: inout Set<String>,
    destinations: DestinationConfig,
    runGuard: RunGuard,
    count: (RunEvent) async -> Void,
    recordFile: (String, String, FileStatus) async -> Void,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visited.contains(threadId), !Task.isCancelled, !runGuard.stopped else { return }
    visited.insert(threadId)

    let data: QuipThreadResponse
    do { data = try await client.getThread(threadId) } catch {
        await log("Failed to fetch thread \(threadId): \(error.localizedDescription)", .error)
        await count(.error)
        runGuard.stop(reason: error.localizedDescription, isAuthFailure: isAuthError(error))
        return
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
    let dirDisplay = notesPath.count > 1 ? notesPath.dropFirst().joined(separator: " / ") : "Root folder"

    // Each thread resolves to exactly one concrete destination: either the setting for
    // its category (document vs. spreadsheet), or — in Ask mode — whatever the user picks.
    let categoryDestination = thread.isSpreadsheet ? destinations.spreadsheet : destinations.document

    let chosenDest: ExportDestination
    if categoryDestination == .ask, let confirm = destinations.confirm {
        guard let picked = await confirm(title, notesPath, thread.isSpreadsheet), !Task.isCancelled else { return }
        chosenDest = picked
    } else {
        chosenDest = categoryDestination
    }

    // --- Apple Notes path ---
    if let nw = writers.notes, let folderId = dirs.notesFolderId, chosenDest == .appleNotes {
        var html = await inlineImages(html: rawHtml, threadId: threadId, client: client, blobCache: blobCache, log: log)
        html = stripLeadingHeading(html: html, title: title)
        let folderDisplay = notesPath.dropFirst().joined(separator: " / ")
        let (fullHtml, checklistItems) = nw.buildHTML(html: html, noteTitle: noteTitle, createdStr: createdStr,
                                                       folderDisplay: folderDisplay, quipLink: quipLink)

        let wasUpdate: Bool
        var noteId = ""
        do {
            let exists = try nw.noteExists(title: noteTitle, folderId: folderId, createdStr: createdStr)
            let oldBody = exists ? try nw.existingBody(title: noteTitle, folderId: folderId, createdStr: createdStr) : nil
            switch await resolveExisting(exists: exists, title: noteTitle, notesPath: notesPath,
                                          oldContent: oldBody, newContent: fullHtml,
                                          confirmOverwrite: destinations.confirmOverwrite) {
            case .unchanged:
                await log("  [unchanged]  \(noteTitle)", .info); await count(.unchanged)
                await recordFile(dirDisplay, noteTitle, .skipped); return
            case .skip:
                await log("  [skipped]  \(noteTitle)", .info); await count(.skipped)
                await recordFile(dirDisplay, noteTitle, .skipped); return
            case .stop: return
            case .proceed(let update):
                wasUpdate = update
                if update {
                    noteId = try nw.updateNote(title: noteTitle, htmlBody: fullHtml, folderId: folderId, createdStr: createdStr)
                } else {
                    noteId = try nw.createNote(title: noteTitle, htmlBody: fullHtml, folderId: folderId)
                }
            }
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle, .error)
            return
        }

        if !checklistItems.isEmpty {
            do {
                try nw.applyChecklistFormatting(noteId: noteId, itemTexts: checklistItems)
            } catch {
                await log("  [warning]  \(noteTitle) — checklist formatting attempt failed: \(error.localizedDescription)", .warning)
            }
        }

        let verb = wasUpdate ? "updated" : "copied"
        await count(wasUpdate ? .updated : .transferred)
        await recordFile(dirDisplay, noteTitle, .copied)
        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                let trashedTitle = "\(noteTitle) (Trashed in Quip)"
                try nw.renameNote(oldTitle: noteTitle, newTitle: trashedTitle, folderId: folderId)
                await log("  [\(verb) + trashed]  \(noteTitle)  (created \(createdStr))", .info)
                await count(.trashed)
            } catch {
                await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
                await count(.error)
            }
        } else {
            await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- Markdown path ---
    if let mw = writers.markdown, let dir = dirs.markdownDir, chosenDest == .markdown {
        let exists = mw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr)

        let resolvedHtml = await resolveImagesForMarkdown(
            html: rawHtml, threadId: threadId, client: client,
            blobCache: blobCache, dir: dir, markdownWriter: mw, log: log
        )
        let processedHtml = stripLeadingHeading(html: resolvedHtml, title: title)
        let newContent = mw.buildContent(title: noteTitle, html: processedHtml, quipLink: quipLink,
                                          createdStr: createdStr, folderPath: notesPath)
        let oldContent = exists ? mw.existingContent(title: noteTitle, dir: dir) : nil

        let wasUpdate: Bool
        switch await resolveExisting(exists: exists, title: noteTitle, notesPath: notesPath,
                                      oldContent: oldContent, newContent: newContent,
                                      confirmOverwrite: destinations.confirmOverwrite) {
        case .unchanged:
            await log("  [unchanged]  \(noteTitle)", .info); await count(.unchanged)
            await recordFile(dirDisplay, noteTitle + ".md", .skipped); return
        case .skip:
            await log("  [skipped]  \(noteTitle)", .info); await count(.skipped)
            await recordFile(dirDisplay, noteTitle + ".md", .skipped); return
        case .stop: return
        case .proceed(let update): wasUpdate = update
        }

        do {
            try mw.writeContent(newContent, title: noteTitle, dir: dir)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".md", .error)
            return
        }

        let verb = wasUpdate ? "updated" : "copied"
        await count(wasUpdate ? .updated : .transferred)
        await recordFile(dirDisplay, noteTitle + ".md", .copied)
        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [\(verb) + trashed]  \(noteTitle)  (created \(createdStr))", .info)
                await count(.trashed)
            } catch {
                await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
                await count(.error)
            }
        } else {
            await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- HTML path ---
    if let hw = writers.html, let dir = dirs.htmlDir, chosenDest == .html {
        let exists = hw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr)

        let resolvedHtml = await resolveImagesForHTML(
            html: rawHtml, threadId: threadId, client: client,
            blobCache: blobCache, dir: dir, htmlWriter: hw, log: log
        )
        let processedHtml = stripLeadingHeading(html: resolvedHtml, title: title)
        let newContent = hw.buildContent(title: noteTitle, html: processedHtml, quipLink: quipLink,
                                          createdStr: createdStr, folderPath: notesPath)
        let oldContent = exists ? hw.existingContent(title: noteTitle, dir: dir) : nil

        let wasUpdate: Bool
        switch await resolveExisting(exists: exists, title: noteTitle, notesPath: notesPath,
                                      oldContent: oldContent, newContent: newContent,
                                      confirmOverwrite: destinations.confirmOverwrite) {
        case .unchanged:
            await log("  [unchanged]  \(noteTitle)", .info); await count(.unchanged)
            await recordFile(dirDisplay, noteTitle + ".html", .skipped); return
        case .skip:
            await log("  [skipped]  \(noteTitle)", .info); await count(.skipped)
            await recordFile(dirDisplay, noteTitle + ".html", .skipped); return
        case .stop: return
        case .proceed(let update): wasUpdate = update
        }

        do {
            try hw.writeContent(newContent, title: noteTitle, dir: dir)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".html", .error)
            return
        }

        let verb = wasUpdate ? "updated" : "copied"
        await count(wasUpdate ? .updated : .transferred)
        await recordFile(dirDisplay, noteTitle + ".html", .copied)
        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [\(verb) + trashed]  \(noteTitle)  (created \(createdStr))", .info)
                await count(.trashed)
            } catch {
                await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
                await count(.error)
            }
        } else {
            await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- Numbers path ---
    if let nuw = writers.numbers, let dir = dirs.numbersDir, chosenDest == .numbers {
        let exists = nuw.noteExists(title: noteTitle, dir: dir)
        let processedHtml = stripLeadingHeading(html: rawHtml, title: title)

        let sheets: [(name: String, rows: [[String]])]
        do {
            sheets = try nuw.buildSheets(title: noteTitle, html: processedHtml, quipLink: quipLink,
                                          createdStr: createdStr, folderPath: notesPath)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".numbers", .error)
            return
        }
        // No existingPreviewText for Numbers (reading a .numbers file back requires opening
        // it in Numbers) — the confirmation still shows a preview of what would be written.
        let newContent = nuw.previewText(sheets: sheets)

        let wasUpdate: Bool
        switch await resolveExisting(exists: exists, title: noteTitle, notesPath: notesPath,
                                      oldContent: nil, newContent: newContent,
                                      confirmOverwrite: destinations.confirmOverwrite) {
        case .unchanged:
            await log("  [unchanged]  \(noteTitle)", .info); await count(.unchanged)
            await recordFile(dirDisplay, noteTitle + ".numbers", .skipped); return
        case .skip:
            await log("  [skipped]  \(noteTitle)", .info); await count(.skipped)
            await recordFile(dirDisplay, noteTitle + ".numbers", .skipped); return
        case .stop: return
        case .proceed(let update): wasUpdate = update
        }

        do {
            try nuw.writeSheets(sheets, title: noteTitle, dir: dir)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".numbers", .error)
            return
        }

        let verb = wasUpdate ? "updated" : "copied"
        await count(wasUpdate ? .updated : .transferred)
        await recordFile(dirDisplay, noteTitle + ".numbers", .copied)
        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [\(verb) + trashed]  \(noteTitle)  (created \(createdStr))", .info)
                await count(.trashed)
            } catch {
                await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
                await count(.error)
            }
        } else {
            await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }

    // --- CSV path ---
    if let cw = writers.csv, let dir = dirs.csvDir, chosenDest == .csv {
        let exists = cw.noteExists(title: noteTitle, dir: dir)
        let processedHtml = stripLeadingHeading(html: rawHtml, title: title)

        let sheets: [(name: String, rows: [[String]])]
        do {
            sheets = try cw.buildSheets(title: noteTitle, html: processedHtml, quipLink: quipLink,
                                        createdStr: createdStr, folderPath: notesPath)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".csv", .error)
            return
        }
        let newContent = SpreadsheetHTMLParser.previewText(sheets: sheets)
        let oldContent = exists ? cw.existingPreviewText(title: noteTitle, dir: dir) : nil

        let wasUpdate: Bool
        switch await resolveExisting(exists: exists, title: noteTitle, notesPath: notesPath,
                                      oldContent: oldContent, newContent: newContent,
                                      confirmOverwrite: destinations.confirmOverwrite) {
        case .unchanged:
            await log("  [unchanged]  \(noteTitle)", .info); await count(.unchanged)
            await recordFile(dirDisplay, noteTitle + ".csv", .skipped); return
        case .skip:
            await log("  [skipped]  \(noteTitle)", .info); await count(.skipped)
            await recordFile(dirDisplay, noteTitle + ".csv", .skipped); return
        case .stop: return
        case .proceed(let update): wasUpdate = update
        }

        do {
            try cw.writeSheets(sheets, title: noteTitle, dir: dir)
        } catch {
            await log("  [error]    \(noteTitle) — \(error.localizedDescription)", .error)
            await count(.error)
            await recordFile(dirDisplay, noteTitle + ".csv", .error)
            return
        }

        let verb = wasUpdate ? "updated" : "copied"
        await count(wasUpdate ? .updated : .transferred)
        for sheet in sheets {
            await recordFile("\(dirDisplay)/\(noteTitle)", sheet.name + ".csv", .copied)
        }
        if deleteAfterCopy && !shared && !trashFolderId.isEmpty {
            do {
                try await client.trashThread(threadId, trashFolderId: trashFolderId)
                await log("  [\(verb) + trashed]  \(noteTitle)  (created \(createdStr))", .info)
                await count(.trashed)
            } catch {
                await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
                await log("  [error]    \(noteTitle) — could not trash: \(error.localizedDescription)", .warning)
                await count(.error)
            }
        } else {
            await log("  [\(verb)]   \(noteTitle)  (created \(createdStr))", .info)
        }
    }
}

private func scanFolder(
    folderId: String,
    notesPath: [String],
    mdPath: [String],
    client: QuipClient,
    writers: Writers,
    deleteAfterCopy: Bool,
    currentUserId: String,
    visitedFolders: inout Set<String>,
    visitedThreads: inout Set<String>,
    destinations: DestinationConfig,
    runGuard: RunGuard,
    summary: inout ScanSummary,
    count: (ScanEvent) async -> Void,
    recordFile: (String, String, FileStatus) async -> Void,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visitedFolders.contains(folderId), !Task.isCancelled, !runGuard.stopped else { return }
    visitedFolders.insert(folderId)

    let data: QuipFolderResponse
    do { data = try await client.getFolder(folderId) } catch {
        await log("Failed to fetch folder \(folderId): \(error.localizedDescription)", .error)
        runGuard.stop(reason: error.localizedDescription, isAuthFailure: isAuthError(error))
        return
    }

    let folderTitle = data.folder.title
    let nextMdPath = skippedInFiles.contains(folderTitle) ? mdPath : mdPath + [folderTitle]
    let nextNotesPath = (writers.notes != nil && skippedInNotes.contains(folderTitle))
        ? notesPath
        : notesPath + [folderTitle]

    var dirs = WriterDirs()

    if let nw = writers.notes {
        do { dirs.notesFolderId = try nw.getOrCreateFolder(path: nextNotesPath) } catch {
            await log("Failed to read Notes folder: \(error.localizedDescription)", .error); return
        }
    }
    if let mw = writers.markdown { dirs.markdownDir = try? mw.ensureFolder(path: nextMdPath) }
    if let hw = writers.html { dirs.htmlDir = try? hw.ensureFolder(path: nextMdPath) }
    if let nuw = writers.numbers { dirs.numbersDir = try? nuw.ensureFolder(path: nextMdPath) }
    if let cw = writers.csv { dirs.csvDir = try? cw.ensureFolder(path: nextMdPath) }

    await prefetchChildren(data.children, client: client)

    for child in data.children {
        if Task.isCancelled || runGuard.stopped { break }
        if let threadId = child.threadId {
            await scanThread(
                threadId: threadId, notesPath: nextMdPath, dirs: dirs,
                client: client, writers: writers, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, visited: &visitedThreads,
                destinations: destinations, runGuard: runGuard, summary: &summary, count: count, recordFile: recordFile, log: log
            )
        } else if let childId = child.folderId {
            await scanFolder(
                folderId: childId, notesPath: nextNotesPath, mdPath: nextMdPath,
                client: client, writers: writers, deleteAfterCopy: deleteAfterCopy,
                currentUserId: currentUserId, visitedFolders: &visitedFolders, visitedThreads: &visitedThreads,
                destinations: destinations, runGuard: runGuard, summary: &summary, count: count, recordFile: recordFile, log: log
            )
        }
    }
}

private func scanThread(
    threadId: String,
    notesPath: [String],
    dirs: WriterDirs,
    client: QuipClient,
    writers: Writers,
    deleteAfterCopy: Bool,
    currentUserId: String,
    visited: inout Set<String>,
    destinations: DestinationConfig,
    runGuard: RunGuard,
    summary: inout ScanSummary,
    count: (ScanEvent) async -> Void,
    recordFile: (String, String, FileStatus) async -> Void,
    log: (String, LogEntry.Level) async -> Void
) async {
    guard !visited.contains(threadId), !Task.isCancelled, !runGuard.stopped else { return }
    visited.insert(threadId)

    let data: QuipThreadResponse
    do { data = try await client.getThread(threadId) } catch {
        await log("Failed to fetch thread \(threadId): \(error.localizedDescription)", .error)
        runGuard.stop(reason: error.localizedDescription, isAuthFailure: isAuthError(error))
        return
    }

    let thread = data.thread
    let title = thread.title
    let createdStr: String
    if let usec = thread.createdUsec {
        let date = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
        createdStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
    } else {
        createdStr = "Unknown"
    }

    let shared = isShared(thread: thread, currentUserId: currentUserId)
    let noteTitle = shared ? title : "\(title) (Private)"
    let categoryDestination = thread.isSpreadsheet ? destinations.spreadsheet : destinations.document
    let dirDisplay = notesPath.count > 1 ? notesPath.dropFirst().joined(separator: " / ") : "Root folder"

    let (handled, exists) = scanExistence(
        categoryDestination: categoryDestination, isSpreadsheet: thread.isSpreadsheet,
        noteTitle: noteTitle, createdStr: createdStr, dirs: dirs, writers: writers
    )
    guard handled else { return }

    // Nothing is actually written during a scan — a document not yet present is shown as
    // "would transfer" (the same green check a real copy gets) and one that already
    // exists is shown as "would update/skip" depending on the run's overwrite setting.
    let fileName = noteTitle + fileExtension(for: categoryDestination)
    await recordFile(dirDisplay, fileName, exists ? .skipped : .copied)

    if exists {
        summary.toUpdate += 1
        await count(.update)
    } else {
        summary.toTransfer += 1
        await count(.transfer)
    }
    if deleteAfterCopy && !shared {
        summary.toTrash += 1
        await count(.trash)
    }
}

private func fileExtension(for destination: ExportDestination) -> String {
    switch destination {
    case .appleNotes, .ask: return ""
    case .markdown: return ".md"
    case .html: return ".html"
    case .numbers: return ".numbers"
    case .csv: return ".csv"
    }
}

// Determines whether a thread would be handled by a configured writer for its category,
// and if so, whether it already exists there. In Ask mode we don't know which destination
// the user will eventually pick, so existence is checked against every writer configured
// for that category and treated as "already exists" if it's found in any of them.
private func scanExistence(
    categoryDestination: ExportDestination,
    isSpreadsheet: Bool,
    noteTitle: String,
    createdStr: String,
    dirs: WriterDirs,
    writers: Writers
) -> (handled: Bool, exists: Bool) {
    func check(_ dest: ExportDestination) -> Bool? {
        switch dest {
        case .appleNotes:
            guard let nw = writers.notes, let folderId = dirs.notesFolderId else { return nil }
            return (try? nw.noteExists(title: noteTitle, folderId: folderId, createdStr: createdStr)) ?? false
        case .markdown:
            guard let mw = writers.markdown, let dir = dirs.markdownDir else { return nil }
            return mw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr)
        case .html:
            guard let hw = writers.html, let dir = dirs.htmlDir else { return nil }
            return hw.noteExists(title: noteTitle, dir: dir, createdStr: createdStr)
        case .numbers:
            guard isSpreadsheet, let nuw = writers.numbers, let dir = dirs.numbersDir else { return nil }
            return nuw.noteExists(title: noteTitle, dir: dir)
        case .csv:
            guard isSpreadsheet, let cw = writers.csv, let dir = dirs.csvDir else { return nil }
            return cw.noteExists(title: noteTitle, dir: dir)
        case .ask:
            return nil
        }
    }

    if categoryDestination != .ask {
        guard let exists = check(categoryDestination) else { return (false, false) }
        return (true, exists)
    }

    let candidates: [ExportDestination] = isSpreadsheet
        ? [.appleNotes, .numbers, .csv, .markdown, .html]
        : [.appleNotes, .markdown, .html]
    let results = candidates.compactMap(check)
    guard !results.isEmpty else { return (false, false) }
    return (true, results.contains(true))
}

// MARK: - Helpers

private enum ExistingAction {
    case proceed(wasUpdate: Bool)
    case unchanged
    case skip
    case stop
}

// Prompts the user when a document already exists in the destination. Without a
// confirmOverwrite callback (shouldn't normally happen), defaults to skipping.
// oldContent/newContent (when both present) let the caller show a diff before overwriting,
// and are compared up front so a document that's byte-for-byte identical skips silently
// instead of prompting.
private func resolveExisting(
    exists: Bool,
    title: String,
    notesPath: [String],
    oldContent: String?,
    newContent: String?,
    confirmOverwrite: ((String, [String], String?, String?) async -> OverwriteChoice)?
) async -> ExistingAction {
    guard exists else { return .proceed(wasUpdate: false) }
    if let oldContent, let newContent, oldContent == newContent { return .unchanged }
    guard let confirmOverwrite else { return .skip }
    switch await confirmOverwrite(title, notesPath, oldContent, newContent) {
    case .overwrite: return .proceed(wasUpdate: true)
    case .skip: return .skip
    case .stop: return .stop
    }
}

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
