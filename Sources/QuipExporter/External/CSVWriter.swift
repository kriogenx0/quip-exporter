import Foundation

// A CSV file can only hold one table, so every spreadsheet becomes a folder named after
// its title containing one CSV per Quip tab (plus a "Quip Info.csv" with metadata) —
// mirroring how Numbers itself exports a multi-sheet document to CSV.
struct CSVWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        let dir = path.dropFirst().reduce(outputDir) { $0.appendingPathComponent(sanitize($1)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func noteExists(title: String, dir: URL) -> Bool {
        let folder = dir.appendingPathComponent(sanitize(title))
        return FileManager.default.fileExists(atPath: folder.path)
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        var sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        guard !sheets.isEmpty else { throw SpreadsheetError.noTablesFound }

        let folderDisplay = folderPath.dropFirst().joined(separator: " / ")
        var infoRows = [["Field", "Value"], ["Title", title], ["Created in Quip", createdStr]]
        if !folderDisplay.isEmpty { infoRows.append(["Quip Folder", folderDisplay]) }
        if !quipLink.isEmpty { infoRows.append(["Quip Link", quipLink]) }
        sheets.append((name: "Quip Info", rows: infoRows))

        let subDir = dir.appendingPathComponent(sanitize(title))
        try? FileManager.default.removeItem(at: subDir)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        for sheet in sheets {
            let file = subDir.appendingPathComponent(sanitize(sheet.name) + ".csv")
            try SpreadsheetHTMLParser.csv(rows: sheet.rows).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
