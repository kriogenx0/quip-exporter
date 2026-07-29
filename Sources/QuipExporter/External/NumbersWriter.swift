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
        let dir = path.dropFirst().reduce(outputDir) { $0.appendingPathComponent(sanitize($1)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func noteExists(title: String, dir: URL) -> Bool {
        let file = dir.appendingPathComponent(sanitize(title) + ".numbers")
        return FileManager.default.fileExists(atPath: file.path)
    }

    func buildSheets(title: String, html: String, quipLink: String, createdStr: String, folderPath: [String]) throws -> [(name: String, rows: [[String]])] {
        var sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        guard !sheets.isEmpty else { throw SpreadsheetError.noTablesFound }

        let folderDisplay = folderPath.dropFirst().joined(separator: " / ")
        var infoRows = [["Field", "Value"], ["Title", title], ["Created in Quip", createdStr]]
        if !folderDisplay.isEmpty { infoRows.append(["Quip Folder", folderDisplay]) }
        if !quipLink.isEmpty { infoRows.append(["Quip Link", quipLink]) }
        sheets.append((name: "Quip Info", rows: infoRows))
        return sheets
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
        _ = try AppleScriptRunner.run(script)
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
        let sheets = try buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeSheets(sheets, title: title, dir: dir)
    }

    // MARK: - AppleScript generation

    // Only one document is ever created (no per-sheet CSV import docs, no cross-document
    // sheet copy), so unlike the old cross-document `duplicate`-based approach there's no
    // longer any need for the window to stay rendered — it's hidden outright rather than
    // just moved off-screen, which depended on AppleScript's position ending up outside
    // every display and reliably stuck flashing the window on some setups. Explicitly
    // specifying the "Blank" template avoids the Template Chooser dialog `make new
    // document` would otherwise show.
    private func buildScript(sheets: [(name: String, rows: [[String]])], targetFile: URL) -> String {
        var lines = ["tell application \"Numbers\""]
        lines.append("\tset doc1 to make new document with properties {document template:template \"Blank\"}")
        lines.append("\trepeat until (exists sheet 1 of doc1)")
        lines.append("\t\tdelay 0.1")
        lines.append("\tend repeat")
        lines.append("\ttry")
        lines.append("\t\tset visible of window 1 of doc1 to false")
        lines.append("\tend try")

        for (index, sheet) in sheets.enumerated() {
            let rowCount = max(1, sheet.rows.count)
            let colCount = max(1, sheet.rows.map { $0.count }.max() ?? 1)
            let sheetRef: String
            if index == 0 {
                sheetRef = "sheet 1 of doc1"
                lines.append("\tset name of \(sheetRef) to \"\(esc(sheet.name))\"")
            } else {
                lines.append("\tmake new sheet at end of sheets of doc1 with properties {name:\"\(esc(sheet.name))\"}")
                sheetRef = "last sheet of doc1"
            }
            // Tables aren't guaranteed to exist (or to have the right dimensions) on a
            // fresh sheet, so any default table is cleared and replaced with one sized
            // exactly to the data before cell values are set.
            lines.append("\trepeat while (count of tables of \(sheetRef)) > 0")
            lines.append("\t\tdelete table 1 of \(sheetRef)")
            lines.append("\tend repeat")
            lines.append("\tmake new table at end of tables of \(sheetRef) with properties {row count:\(rowCount), column count:\(colCount)}")
            let tableRef = "table 1 of \(sheetRef)"
            for (r, row) in sheet.rows.enumerated() {
                for (c, value) in row.enumerated() where !value.isEmpty {
                    lines.append("\tset value of cell \(c + 1) of row \(r + 1) of \(tableRef) to \"\(esc(value))\"")
                }
            }
        }

        lines.append("\tsave doc1 in POSIX file \"\(esc(targetFile.path))\"")
        lines.append("\tclose doc1 saving no")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
