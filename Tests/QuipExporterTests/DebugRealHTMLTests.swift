import XCTest
@testable import QuipExporter

// Drives real Numbers via AppleScript against cached real Quip API responses, so it's
// gated the same way as AppleScriptContentFidelityTests.swift.
final class DebugRealHTMLTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_UI_TESTS=1 (or run `make test`) to run tests that drive real Notes/Numbers")
        }
    }

    func testRealCachedSpreadsheetHTML() throws {
        let files = [
            "threads_ACV9AAAYMXO.json",
            "threads_acW9AAPbTrY.json",
            "threads_ACO9AAnqAV6.json",
            "threads_add9AAIT1Ls.json",
            "threads_aPK9AAqkv3A.json"
        ]
        let base = ("~/Library/Application Support/QuipExporter/APICache" as NSString).expandingTildeInPath
        for file in files {
            let path = (base as NSString).appendingPathComponent(file)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            guard let html = findHTML(in: json) else {
                print("=== \(file): NO HTML FOUND ===")
                continue
            }
            let sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
            print("=== \(file) ===")
            print("html length: \(html.count)")
            print("sheets found: \(sheets.count)")
            for sheet in sheets {
                let nonEmptyRows = sheet.rows.filter { row in row.contains { !$0.isEmpty } }
                print("  sheet '\(sheet.name)': \(sheet.rows.count) rows, \(nonEmptyRows.count) non-empty rows, first row: \(sheet.rows.first ?? [])")
            }
        }
    }

    func testWriteRealSheetToNumbers() throws {
        let base = ("~/Library/Application Support/QuipExporter/APICache" as NSString).expandingTildeInPath
        let source = try cachedSpreadsheet(in: URL(fileURLWithPath: base))
        let data = try Data(contentsOf: source)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let html = try XCTUnwrap(findHTML(in: json))
        let thread = json["thread"] as? [String: Any]
        let title = (thread?["title"] as? String) ?? source.deletingPathExtension().lastPathComponent
        let outDir = URL(fileURLWithPath: "/tmp/numbers_debug_out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let writer = NumbersWriter(outputDir: outDir)
        let sheets = try writer.buildSheets(title: title, html: html, quipLink: "https://example.com", createdStr: "2026-01-01", folderPath: [])
        print("Exporting complete cached spreadsheet '\(title)' from \(source.lastPathComponent)")
        print("Built \(sheets.count) sheets: \(sheets.map { "\($0.name): \($0.rows.count) rows" })")
        try writer.writeSheets(sheets, title: title, dir: outDir)

        let output = outDir.appendingPathComponent(FileExportSupport.sanitize(title) + ".numbers")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        try assertNumbersDocument(output, exactlyMatches: sheets)
        print("Wrote and verified every cell in \(output.path)")
    }

    // Pure string generation, no Apple Events — safe to run outside RUN_UI_TESTS gate.
    func testDumpRealSheetScript() throws {
        let base = ("~/Library/Application Support/QuipExporter/APICache" as NSString).expandingTildeInPath
        let path = (base as NSString).appendingPathComponent("threads_add9AAIT1Ls.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let html = findHTML(in: json)!
        let outDir = URL(fileURLWithPath: "/tmp/numbers_debug_out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let writer = NumbersWriter(outputDir: outDir)
        let sheets = try writer.buildSheets(title: "DebugExport", html: html, quipLink: "https://example.com", createdStr: "2026-01-01", folderPath: [])
        let script = writer.buildScript(sheets: sheets, targetFile: outDir.appendingPathComponent("DebugExport.numbers"))
        try script.write(to: URL(fileURLWithPath: "/tmp/real_numbers_script.applescript"), atomically: true, encoding: .utf8)
        print("Wrote script (\(script.count) chars) to /tmp/real_numbers_script.applescript")
    }

    func findHTML(in obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            if let html = dict["html"] as? String {
                return html
            }
            for (_, v) in dict {
                if let found = findHTML(in: v) { return found }
            }
        } else if let arr = obj as? [Any] {
            for v in arr {
                if let found = findHTML(in: v) { return found }
            }
        }
        return nil
    }

    // NUMBERS_TEST_THREAD_ID can select a particular cached spreadsheet. Otherwise use
    // the largest one, which gives this explicit integration test the broadest realistic
    // coverage instead of quietly exercising a tiny fixture.
    private func cachedSpreadsheet(in cacheDir: URL) throws -> URL {
        let requestedID = ProcessInfo.processInfo.environment["NUMBERS_TEST_THREAD_ID"]
        let files = try FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            url.lastPathComponent.hasPrefix("threads_") && url.pathExtension == "json"
        }

        if let requestedID {
            let requested = cacheDir.appendingPathComponent("threads_\(requestedID).json")
            guard FileManager.default.fileExists(atPath: requested.path) else {
                throw XCTSkip("No cached Quip response for thread \(requestedID) at \(requested.path)")
            }
            return requested
        }

        let spreadsheets = files.filter { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thread = json["thread"] as? [String: Any] else { return false }
            return thread["type"] as? String == "spreadsheet"
        }
        guard let largest = spreadsheets.max(by: { fileSize($0) < fileSize($1) }) else {
            throw XCTSkip("No cached Quip spreadsheets found in \(cacheDir.path)")
        }
        return largest
    }

    private func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func assertNumbersDocument(
        _ file: URL,
        exactlyMatches expectedSheets: [(name: String, rows: [[String]])]
    ) throws {
        let expected = expectedSheets.map { sheet in
            (
                name: sheet.name,
                rowCount: max(1, sheet.rows.count),
                columnCount: max(1, sheet.rows.map(\.count).max() ?? 1),
                values: sheet.rows.flatMap { row in
                    row + Array(repeating: "", count: max(0, (sheet.rows.map(\.count).max() ?? 1) - row.count))
                }
            )
        }
        let script = """
        tell application "Numbers"
            set doc1 to open POSIX file "\(appleScriptEscape(file.path))"
            repeat until (exists sheet 1 of doc1)
                delay 0.1
            end repeat
            set output to ""
            repeat with s in sheets of doc1
                set t to table 1 of s
                set output to output & (name of s) & return & (row count of t) & return & (column count of t) & return
                repeat with r from 1 to (row count of t)
                    repeat with c from 1 to (column count of t)
                        set v to value of cell c of row r of t
                        if v is missing value then set v to ""
                        set output to output & v & character id 30
                    end repeat
                end repeat
                set output to output & character id 29
            end repeat
            close doc1 saving no
            return output
        end tell
        """
        let dump = try AppleScriptRunner.run(script, timeout: 900)
        let actualSheets = dump.split(separator: Character(UnicodeScalar(29)), omittingEmptySubsequences: true)
        XCTAssertEqual(actualSheets.count, expected.count, "sheet count differs")

        for (index, expectedSheet) in expected.enumerated() where index < actualSheets.count {
            let parts = actualSheets[index].split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
            XCTAssertGreaterThanOrEqual(parts.count, 4, "malformed readback for sheet \(index + 1)")
            guard parts.count >= 4 else { continue }
            XCTAssertEqual(String(parts[0]), expectedSheet.name)
            XCTAssertEqual(Int(parts[1]), expectedSheet.rowCount, "row count differs in \(expectedSheet.name)")
            XCTAssertEqual(Int(parts[2]), expectedSheet.columnCount, "column count differs in \(expectedSheet.name)")
            let values = parts[3].split(separator: Character(UnicodeScalar(30)), omittingEmptySubsequences: false).map(String.init)
            XCTAssertEqual(values, expectedSheet.values, "cell values differ in \(expectedSheet.name)")
        }
    }

    private func appleScriptEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
