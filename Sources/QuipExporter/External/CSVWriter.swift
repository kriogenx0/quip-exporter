import Foundation

// A CSV file can only hold one table, so every spreadsheet becomes a folder named after
// its title containing one CSV per Quip tab (plus a "Quip Info.csv" with metadata) —
// mirroring how Numbers itself exports a multi-sheet document to CSV.
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

    func writeSheets(_ sheets: [(name: String, rows: [[String]])], title: String, dir: URL) throws {
        let subDir = dir.appendingPathComponent(sanitize(title))
        try? FileManager.default.removeItem(at: subDir)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        for sheet in sheets {
            let file = subDir.appendingPathComponent(sanitize(sheet.name) + ".csv")
            try SpreadsheetHTMLParser.csv(rows: sheet.rows).write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // Reconstructs the same "== name ==" preview text buildSheets/previewText would
    // produce, but from the CSV files already on disk — for diffing against new content.
    func existingPreviewText(title: String, dir: URL) -> String? {
        let subDir = dir.appendingPathComponent(sanitize(title))
        guard let files = try? FileManager.default.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "csv" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return nil }
        guard !files.isEmpty else { return nil }
        let sections = files.compactMap { file -> String? in
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return "== \(file.deletingPathExtension().lastPathComponent) ==\n\(content)"
        }
        return sections.joined(separator: "\n\n")
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        let sheets = try buildSheets(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeSheets(sheets, title: title, dir: dir)
    }

    private func sanitize(_ name: String) -> String {
        FileExportSupport.sanitize(name)
    }
}
