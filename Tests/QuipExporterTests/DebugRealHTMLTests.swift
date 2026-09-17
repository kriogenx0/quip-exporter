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
        let path = (base as NSString).appendingPathComponent("threads_add9AAIT1Ls.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let html = findHTML(in: json)!
        let outDir = URL(fileURLWithPath: "/tmp/numbers_debug_out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let writer = NumbersWriter(outputDir: outDir)
        let sheets = try writer.buildSheets(title: "DebugExport", html: html, quipLink: "https://example.com", createdStr: "2026-01-01", folderPath: [])
        print("Built \(sheets.count) sheets: \(sheets.map { "\($0.name): \($0.rows.count) rows" })")
        try writer.writeSheets(sheets, title: "DebugExport", dir: outDir)
        print("Wrote to \(outDir.appendingPathComponent("DebugExport.numbers").path)")
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
}
