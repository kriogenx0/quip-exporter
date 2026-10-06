import Foundation

// A CSV file can only hold one table, so every spreadsheet becomes a folder named after
// its title containing one CSV per Quip tab, named "<title>-sheet1.csv", "<title>-sheet2.csv",
// … (plus a "Quip Info.csv" with metadata) — mirroring how Numbers itself exports a
// multi-sheet document to CSV.
struct CSVWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        try FileExportSupport.ensureFolder(path: path, in: outputDir)
    }

    func noteExists(title: String, dir: URL) -> Bool {
        let folder = dir.appendingPathComponent(sanitize(title))
        return FileManager.default.fileExists(atPath: folder.path)
    }

    func buildSheets(title: String, html: String, quipLink: String, createdStr: String, folderPath: [String]) throws -> [(name: String, rows: [[String]])] {
        try SpreadsheetHTMLParser.buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
    }

    // One file name per entry in `sheets`. buildSheets always appends the "Quip Info"
    // metadata sheet last, so everything before it is a real tab and gets numbered.
    func fileNames(for sheets: [(name: String, rows: [[String]])], title: String) -> [String] {
        sheets.indices.map { index in
            index == sheets.count - 1 ? "Quip Info.csv" : "\(sanitize(title))-sheet\(index + 1).csv"
        }
    }

    func writeSheets(_ sheets: [(name: String, rows: [[String]])], title: String, dir: URL) throws {
        let subDir = dir.appendingPathComponent(sanitize(title))
        try? FileManager.default.removeItem(at: subDir)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        for (sheet, name) in zip(sheets, fileNames(for: sheets, title: title)) {
            let file = subDir.appendingPathComponent(name)
            try SpreadsheetHTMLParser.csv(rows: sheet.rows).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // Preview text keyed by output file name rather than tab name, so it can be compared
    // against existingPreviewText (the same files read back from disk).
    func previewText(sheets: [(name: String, rows: [[String]])], title: String) -> String {
        zip(sheets, fileNames(for: sheets, title: title)).map { sheet, name in
            "== \(name) ==\n\(SpreadsheetHTMLParser.csv(rows: sheet.rows))"
        }.joined(separator: "\n\n")
    }

    // Reconstructs the same text previewText would produce, but from the CSV files
    // already on disk — for diffing against new content.
    func existingPreviewText(title: String, dir: URL, sheets: [(name: String, rows: [[String]])]) -> String? {
        let subDir = dir.appendingPathComponent(sanitize(title))
        let sections = fileNames(for: sheets, title: title).compactMap { name -> String? in
            guard let content = try? String(contentsOf: subDir.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return "== \(name) ==\n\(content)"
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        let sheets = try buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeSheets(sheets, title: title, dir: dir)
    }

    private func sanitize(_ name: String) -> String {
        FileExportSupport.sanitize(name)
    }
}
