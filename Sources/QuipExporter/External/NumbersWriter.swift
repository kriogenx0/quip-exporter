import Foundation

// Drives the real Numbers app via AppleScript. Builds every sheet/table/cell natively
// in a single document, rather than importing each tab as its own CSV-backed document
// and merging sheets across documents — that approach opened one Numbers window per
// sheet and relied on cross-document `duplicate`, which reliably failed with "Sheets
// can not be copied" (-1717) regardless of window visibility/position, and visibly
// flashed a window per sheet. Building natively means only one document (and window)
// ever exists for the whole export.
struct NumbersWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        try FileExportSupport.ensureFolder(path: path, in: outputDir)
    }

    func noteExists(title: String, dir: URL) -> Bool {
        let file = dir.appendingPathComponent(sanitize(title) + ".numbers")
        return FileManager.default.fileExists(atPath: file.path)
    }

    func buildSheets(title: String, html: String, quipLink: String, createdStr: String, folderPath: [String]) throws -> [(name: String, rows: [[String]])] {
        try SpreadsheetHTMLParser.buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
    }

    // Numbers has no scriptable way to read a .numbers file's contents back out cheaply
    // (it would require opening the file in Numbers itself), so unlike CSV there's no
    // existingPreviewText — only a preview of what's about to be written.
    func previewText(sheets: [(name: String, rows: [[String]])]) -> String {
        SpreadsheetHTMLParser.previewText(sheets: sheets)
    }

    func writeSheets(_ sheets: [(name: String, rows: [[String]])], title: String, dir: URL) throws {
        let targetFile = dir.appendingPathComponent(sanitize(title) + ".numbers")
        try? FileManager.default.removeItem(at: targetFile)
        suppressWhereToSaveDialog()
        let script = buildScript(sheets: sheets, targetFile: targetFile)
        // Numbers redoes layout/recalculation after every column write, which for a
        // large real-world spreadsheet is slow enough that the default 3-minute budget
        // (fine for Notes) isn't enough headroom.
        _ = try AppleScriptRunner.run(script, timeout: 900)
        // osascript exiting cleanly only means Numbers accepted the `save` command, not
        // that the file actually landed — confirm it before reporting success.
        guard FileManager.default.fileExists(atPath: targetFile.path) else {
            throw SpreadsheetError.fileNotWritten(path: targetFile.path)
        }
    }

    // Saving a brand-new iWork document via AppleScript can pop a "Where do you want to
    // save this document?" (iCloud vs. this Mac) sheet that nothing here can dismiss —
    // the script then hangs on `save` until AppleScriptRunner's timeout kills it, having
    // never written the file. Numbers checks this preference itself before showing that
    // sheet, so setting it once is enough to make every subsequent save go straight to
    // the POSIX path we ask for.
    private func suppressWhereToSaveDialog() {
        UserDefaults(suiteName: "com.apple.iWork.Numbers")?.set(false, forKey: "ShowWhereToSaveDocumentDialog")
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        saveDebugHTML(html)
        let sheets = try buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeSheets(sheets, title: title, dir: dir)
    }

    // Temporary debugging aid: SpreadsheetHTMLParser was written without ever seeing real
    // Quip spreadsheet HTML, so cells reported as empty/missing need a real sample to
    // diagnose against. Kept alongside AppleScriptRunner's last-failed.applescript pattern.
    private func saveDebugHTML(_ html: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuipExporter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? html.write(to: dir.appendingPathComponent("last-spreadsheet.html"), atomically: true, encoding: .utf8)
    }

    // MARK: - AppleScript generation

    // Only one document is ever created (no per-sheet CSV import docs, no cross-document
    // sheet copy), so unlike the old cross-document `duplicate`-based approach there's no
    // longer any need for the window to stay rendered — it's hidden once everything is
    // built, rather than just moved off-screen, which depended on AppleScript's position
    // ending up outside every display and reliably stuck flashing the window on some
    // setups. Explicitly specifying the "Blank" template avoids the Template Chooser
    // dialog `make new document` would otherwise show.
    //
    // `make new sheet`/`make new table` (and `duplicate`/`move` as substitutes) all fail
    // with "AppleEvent handler failed (-10000)" on Numbers 15.3/macOS 26 — reproducible
    // even against a bare new document, so it's a Numbers regression rather than
    // something about this script. The only working way found to add a sheet is driving
    // the "Insert > Sheet" menu item via System Events UI scripting, which needs the
    // window on-screen and Numbers frontmost, hence hiding the window only at the end.
    // Every sheet (including the first) then reuses its own pre-existing default table,
    // resized in place, rather than deleting and remaking it.
    //
    // Internal rather than private so tests can inspect/execute the generated script
    // directly without going through AppleScriptRunner (see AppleScriptContentFidelityTests).
    func buildScript(sheets: [(name: String, rows: [[String]])], targetFile: URL) -> String {
        // Numbers redoes layout/recalculation after every cell write, and for a real
        // spreadsheet that's slow enough to blow past AppleScript's default 2-minute
        // per-Apple-Event timeout ("AppleEvent timed out (-1712)"). Raising it here
        // overrides that default for every event sent within this script.
        var lines = ["with timeout of 900 seconds", "tell application \"Numbers\"", "\tactivate"]
        lines.append("\tset doc1 to make new document with properties {document template:template \"Blank\"}")
        lines.append("\trepeat until (exists sheet 1 of doc1)")
        lines.append("\t\tdelay 0.1")
        lines.append("\tend repeat")
        lines.append("\ttry")

        for (index, sheet) in sheets.enumerated() {
            let rowCount = max(1, sheet.rows.count)
            let colCount = max(1, sheet.rows.map { $0.count }.max() ?? 1)
            let sheetRef: String
            if index == 0 {
                sheetRef = "sheet 1 of doc1"
            } else {
                // A fixed delay rather than polling `count of sheets of doc1` right after
                // the click: querying Numbers over AppleEvents while its UI is mid-click
                // reliably deadlocked the whole script during testing.
                lines.append("\t\tactivate")
                lines.append("\t\tdelay 0.3")
                lines.append("\t\ttell application \"System Events\" to tell process \"Numbers\" to click menu item \"Sheet\" of menu \"Insert\" of menu bar 1")
                lines.append("\t\tdelay 0.5")
                sheetRef = "last sheet of doc1"
            }
            lines.append("\t\tset name of \(sheetRef) to \"\(esc(sheet.name))\"")
            // A fresh sheet may have more than one default table; only the first is kept
            // and resized to fit the data (see the `make new table` note above).
            lines.append("\t\trepeat while (count of tables of \(sheetRef)) > 1")
            lines.append("\t\t\tdelete table 2 of \(sheetRef)")
            lines.append("\t\tend repeat")
            lines.append("\t\tset row count of table 1 of \(sheetRef) to \(rowCount)")
            lines.append("\t\tset column count of table 1 of \(sheetRef) to \(colCount)")
            let tableRef = "table 1 of \(sheetRef)"
            // "set value of every cell of column N to {list}" (and the row/range
            // equivalents) also fail on this Numbers build ("Can't make {...} into type
            // number, date, text, boolean or missing value"), even though the
            // single-cell form works — so despite being far chattier, cell-by-cell is
            // what actually writes data. Blank source cells are skipped since a resized
            // table's cells already default to empty.
            //
            // Format is forced to text before every write so Numbers never
            // reinterprets a date- or number-looking source string (e.g. "Jan 1, 2026")
            // into its own type and reformats what's displayed.
            for r in 0..<rowCount {
                for c in 0..<colCount {
                    let value = (r < sheet.rows.count && c < sheet.rows[r].count) ? sheet.rows[r][c] : ""
                    guard !value.isEmpty else { continue }
                    let cellRef = "cell \(r + 1) of column \(c + 1) of \(tableRef)"
                    lines.append("\t\tset format of \(cellRef) to text")
                    lines.append("\t\tset value of \(cellRef) to \"\(esc(value))\"")
                }
            }
        }

        lines.append("\t\ttry")
        lines.append("\t\t\tset visible of window 1 of doc1 to false")
        lines.append("\t\tend try")
        lines.append("\t\tsave doc1 in POSIX file \"\(esc(targetFile.path))\"")
        lines.append("\ton error errMsg")
        lines.append("\t\tclose doc1 saving no")
        lines.append("\t\terror errMsg")
        lines.append("\tend try")
        lines.append("\tclose doc1 saving no")
        lines.append("end tell")
        lines.append("end timeout")
        return lines.joined(separator: "\n")
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }

    private func sanitize(_ name: String) -> String {
        FileExportSupport.sanitize(name)
    }
}
