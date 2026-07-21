import Foundation

// Drives the real Numbers app via AppleScript: each detected HTML table becomes a CSV,
// Numbers imports each CSV into its own document, and the resulting sheets are merged
// into one document (Numbers has no scriptable "import CSV as sheet N" command).
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
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let csvPaths = try sheets.enumerated().map { index, sheet -> URL in
            let path = tmpDir.appendingPathComponent("sheet\(index + 1).csv")
            try SpreadsheetHTMLParser.csv(rows: sheet.rows).write(to: path, atomically: true, encoding: .utf8)
            return path
        }

        let targetFile = dir.appendingPathComponent(sanitize(title) + ".numbers")
        try? FileManager.default.removeItem(at: targetFile)
        let script = buildScript(csvPaths: csvPaths, names: sheets.map { $0.name }, targetFile: targetFile)
        _ = try AppleScriptRunner.run(script)
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        let sheets = try buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeSheets(sheets, title: title, dir: dir)
    }

    // MARK: - AppleScript generation

    // `duplicate ... to end of sheets of doc1` is asynchronous — Numbers can return from
    // the command before the sheet actually lands in doc1, so a fixed `delay` after it is
    // a race that silently drops sheets under load. Polling the sheet count until it
    // actually increases (instead of guessing a delay) is what makes the merge reliable.
    // Windows are moved off-screen immediately after each doc opens (and Numbers is never
    // `activate`d) so the export doesn't visibly take over the screen. Setting `visible to
    // false` instead of repositioning was tried first, but Numbers' cross-document
    // `duplicate` needs the window to still be a normal, rendered window to work — a hidden
    // window makes it fail with "Sheets can not be copied" (-1717).
    private func buildScript(csvPaths: [URL], names: [String], targetFile: URL) -> String {
        var lines = ["tell application \"Numbers\""]
        lines.append("\tset doc1 to open POSIX file \"\(esc(csvPaths[0].path))\"")
        lines += waitAndMoveOffscreen(doc: "doc1")
        lines.append("\tset name of sheet 1 of doc1 to \"\(esc(names[0]))\"")
        for i in 1..<csvPaths.count {
            let docVar = "doc\(i + 1)"
            lines.append("\tset \(docVar) to open POSIX file \"\(esc(csvPaths[i].path))\"")
            lines += waitAndMoveOffscreen(doc: docVar)
            lines.append("\tset sheetCountBefore to (count of sheets of doc1)")
            lines.append("\tduplicate (sheet 1 of \(docVar)) to end of sheets of doc1")
            lines.append("\trepeat until (count of sheets of doc1) > sheetCountBefore")
            lines.append("\t\tdelay 0.1")
            lines.append("\tend repeat")
            lines.append("\tset name of (last sheet of doc1) to \"\(esc(names[i]))\"")
            lines.append("\tclose \(docVar) saving no")
        }
        lines.append("\tsave doc1 in POSIX file \"\(esc(targetFile.path))\"")
        lines.append("\tclose doc1 saving no")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private func waitAndMoveOffscreen(doc: String) -> [String] {
        [
            "\trepeat until (exists sheet 1 of \(doc))",
            "\t\tdelay 0.1",
            "\tend repeat",
            "\ttry",
            "\t\tset position of window 1 of \(doc) to {-2000, -2000}",
            "\tend try",
        ]
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
