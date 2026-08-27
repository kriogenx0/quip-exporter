import XCTest
@testable import QuipExporter

// Content-fidelity tests for the plain-file writers (Markdown/HTML/CSV): each asserts
// that everything in a known HTML fixture actually lands in the file written to disk,
// not just that a file gets created. Pure FileManager I/O, no AppleScript — always safe
// to run under `make test-quick`.
final class FileWriterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private let fixtureHTML = """
    <h1>Ignored Title</h1>\
    <p>Plain paragraph with <strong>bold</strong> and <a href="https://example.com">a link</a>.</p>\
    <ul><li>First item</li><li>Second item</li></ul>
    """

    // MARK: - FileExportSupport

    func testSanitizeStripsForbiddenCharacters() {
        XCTAssertEqual(FileExportSupport.sanitize("A/B\\C:D*E?F\"G<H>I|J"), "A-B-C-D-E-F-G-H-I-J")
    }

    func testEnsureFolderCreatesNestedDirectory() throws {
        let dir = try FileExportSupport.ensureFolder(path: ["Quip Export", "Sub Folder"], in: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(dir.lastPathComponent, "Sub Folder")
    }

    // MARK: - MarkdownWriter

    func testMarkdownWriterCreatesFileWithFrontmatterAndConvertedContent() throws {
        let writer = MarkdownWriter(outputDir: tempDir)
        let dir = try writer.ensureFolder(path: ["Quip Export"])
        try writer.writeNote(title: "My Doc", html: fixtureHTML, dir: dir,
                              quipLink: "https://quip.com/abc", createdStr: "Jan 1, 2026",
                              folderPath: ["Quip Export", "Notes"])

        let file = dir.appendingPathComponent("My Doc.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let content = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(content.contains("title: \"My Doc\""))
        XCTAssertTrue(content.contains("created: Jan 1, 2026"))
        XCTAssertTrue(content.contains("quip_folder: \"Notes\""))
        XCTAssertTrue(content.contains("quip_link: \"https://quip.com/abc\""))
        XCTAssertTrue(content.contains("**bold**"))
        XCTAssertTrue(content.contains("[a link](https://example.com)"))
        XCTAssertTrue(content.contains("- First item"))
        XCTAssertTrue(content.contains("- Second item"))
        XCTAssertTrue(writer.noteExists(title: "My Doc", dir: dir, createdStr: "Jan 1, 2026"))
    }

    // MARK: - HTMLWriter

    func testHTMLWriterCreatesFileWithMetadataAndRawContent() throws {
        let writer = HTMLWriter(outputDir: tempDir)
        let dir = try writer.ensureFolder(path: ["Quip Export"])
        try writer.writeNote(title: "My Doc", html: fixtureHTML, dir: dir,
                              quipLink: "https://quip.com/abc", createdStr: "Jan 1, 2026",
                              folderPath: ["Quip Export", "Notes"])

        let file = dir.appendingPathComponent("My Doc.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let content = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(content.contains("content=\"Jan 1, 2026\""))
        XCTAssertTrue(content.contains("quip-folder\" content=\"Notes\""))
        XCTAssertTrue(content.contains("quip-link\" content=\"https://quip.com/abc\""))
        XCTAssertTrue(content.contains(fixtureHTML))
        XCTAssertTrue(writer.noteExists(title: "My Doc", dir: dir, createdStr: "Jan 1, 2026"))
    }

    // MARK: - CSVWriter

    func testCSVWriterCreatesOneFilePerSheetPlusQuipInfo() throws {
        let writer = CSVWriter(outputDir: tempDir)
        let dir = try writer.ensureFolder(path: ["Quip Export"])
        let html = "<h2>Stations</h2><table><tr><td>Name</td><td>Code</td></tr><tr><td>Central</td><td>C1</td></tr></table>"

        let sheets = try writer.buildSheets(title: "My Sheet", html: html, quipLink: "https://quip.com/xyz",
                                             createdStr: "Jan 1, 2026", folderPath: ["Quip Export", "Sheets"])
        try writer.writeSheets(sheets, title: "My Sheet", dir: dir)

        let sheetFolder = dir.appendingPathComponent("My Sheet")
        XCTAssertTrue(writer.noteExists(title: "My Sheet", dir: dir))

        let stationsCSV = try String(contentsOf: sheetFolder.appendingPathComponent("Stations.csv"), encoding: .utf8)
        XCTAssertEqual(stationsCSV, "Name,Code\r\nCentral,C1")

        let infoCSV = try String(contentsOf: sheetFolder.appendingPathComponent("Quip Info.csv"), encoding: .utf8)
        XCTAssertTrue(infoCSV.contains("Title,My Sheet"))
        XCTAssertTrue(infoCSV.contains("Created in Quip,\"Jan 1, 2026\""))
        XCTAssertTrue(infoCSV.contains("Sheets"))
        XCTAssertTrue(infoCSV.contains("https://quip.com/xyz"))
    }
}
