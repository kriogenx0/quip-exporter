import XCTest
@testable import QuipExporter

// These tests drive real Notes.app/Numbers.app via AppleScript and assert that content
// written through the real export pipeline round-trips correctly — not just that a
// note/file gets created. They're skipped by default (a bare `swift test` run, and so
// `make test-quick`) because a `swift test` process has a different TCC/Automation
// identity than the built .app: the first real run may pop a permission prompt or hang
// on AppleScriptRunner's timeout instead of reusing consent already granted to the app.
// Run them deliberately with `make test`, which sets RUN_UI_TESTS=1.
final class AppleScriptContentFidelityTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_UI_TESTS=1 (or run `make test`) to run tests that drive real Notes/Numbers")
        }
    }

    // MARK: - Numbers

    // Exercises the full pipeline (HTML -> parsed sheets -> AppleScript write -> real
    // .numbers document) and reads the cell values back out via a second AppleScript
    // pass, guarding against the exact "empty/missing data" failure mode this writer has
    // seen before — asserting a file was created isn't enough to catch that.
    func testNumbersWriterRoundTripsSheetContent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = NumbersWriter(outputDir: tempDir)
        let html = "<h2>Stations</h2><table><tr><td>Name</td><td>Code</td></tr><tr><td>QuipAlpha</td><td>QuipBeta</td></tr></table>"
        let sheets = try writer.buildSheets(title: "Fidelity Test", html: html, quipLink: "",
                                             createdStr: "Jan 1, 2026", folderPath: ["Quip Export"])
        try writer.writeSheets(sheets, title: "Fidelity Test", dir: tempDir)

        let file = tempDir.appendingPathComponent("Fidelity Test.numbers")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        let dump = try readBackNumbersSheet(at: file, sheetName: "Stations")
        XCTAssertTrue(dump.contains("Name"), "expected header row in: \(dump)")
        XCTAssertTrue(dump.contains("Code"), "expected header row in: \(dump)")
        XCTAssertTrue(dump.contains("QuipAlpha"), "expected data row in: \(dump)")
        XCTAssertTrue(dump.contains("QuipBeta"), "expected data row in: \(dump)")
    }

    // Opens the just-written .numbers file and dumps its named sheet's table back out as
    // tab/newline-delimited text — the only way to verify cell contents, since Numbers
    // has no cheaper scriptable read path (see NumbersWriter.previewText's comment).
    private func readBackNumbersSheet(at file: URL, sheetName: String) throws -> String {
        let script = """
        tell application "Numbers"
            set doc1 to open POSIX file "\(file.path)"
            repeat until (exists sheet 1 of doc1)
                delay 0.1
            end repeat
            set targetSheet to missing value
            repeat with s in sheets of doc1
                if name of s is "\(sheetName)" then set targetSheet to s
            end repeat
            if targetSheet is missing value then
                close doc1 saving no
                return ""
            end if
            set t to table 1 of targetSheet
            set output to ""
            set rc to row count of t
            set cc to column count of t
            repeat with r from 1 to rc
                repeat with c from 1 to cc
                    set output to output & ((value of cell c of row r of t) as string) & tab
                end repeat
                set output to output & linefeed
            end repeat
            close doc1 saving no
            return output
        end tell
        """
        return try AppleScriptRunner.run(script)
    }

    // MARK: - Notes

    func testNotesWriterRoundTripsBodyContent() throws {
        let writer = NotesWriter(account: "")
        let folderId = try writer.getOrCreateFolder(path: ["Quip Export", "Fidelity Test"])
        let title = "Fidelity Test \(UUID().uuidString.prefix(8))"
        let html = "<p>Plain paragraph with <strong>bold</strong> text.</p><ul><li>First item</li></ul>"
        let (fullHTML, _) = writer.buildHTML(html: html, noteTitle: title, createdStr: "Jan 1, 2026",
                                              folderDisplay: "Fidelity Test", quipLink: "")
        let noteId = try writer.createNote(title: title, htmlBody: fullHTML, folderId: folderId)
        defer {
            _ = try? AppleScriptRunner.run("""
            tell application "Notes"
                delete note id "\(noteId)"
            end tell
            """)
        }

        XCTAssertTrue(try writer.noteExists(title: title, folderId: folderId, createdStr: "Jan 1, 2026"))
        let body = try writer.existingBody(title: title, folderId: folderId, createdStr: "Jan 1, 2026")
        XCTAssertNotNil(body)
        XCTAssertTrue(body?.contains("bold") ?? false, "expected bold text in: \(body ?? "")")
        XCTAssertTrue(body?.contains("Plain paragraph") ?? false, "expected paragraph text in: \(body ?? "")")
        XCTAssertTrue(body?.contains("First item") ?? false, "expected list item text in: \(body ?? "")")
    }
}
