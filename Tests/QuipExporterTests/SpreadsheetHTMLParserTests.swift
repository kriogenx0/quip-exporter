import XCTest
@testable import QuipExporter

final class SpreadsheetHTMLParserTests: XCTestCase {
    func testParseSheetsSingleTable() {
        let html = "<table><tr><td>A</td><td>B</td></tr><tr><td>1</td><td>2</td></tr></table>"
        let sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].name, "Sheet 1")
        XCTAssertEqual(sheets[0].rows, [["A", "B"], ["1", "2"]])
    }

    func testParseSheetsUsesPrecedingHeadingAsName() {
        let html = "<h2>Stations</h2><table><tr><td>X</td></tr></table>"
        let sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].name, "Stations")
    }

    func testParseSheetsHandlesColspan() {
        let html = "<table><tr><td colspan=\"2\">A</td><td>B</td></tr></table>"
        let sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        XCTAssertEqual(sheets[0].rows, [["A", "", "B"]])
    }

    func testParseSheetsMultipleTables() {
        let html = "<h1>One</h1><table><tr><td>1</td></tr></table><h1>Two</h1><table><tr><td>2</td></tr></table>"
        let sheets = SpreadsheetHTMLParser.parseSheets(fromHTML: html)
        XCTAssertEqual(sheets.map { $0.name }, ["One", "Two"])
    }

    func testCSVEscapesCommasAndQuotes() {
        let csv = SpreadsheetHTMLParser.csv(rows: [["a,b", "say \"hi\"", "plain"]])
        XCTAssertEqual(csv, "\"a,b\",\"say \"\"hi\"\"\",plain")
    }

    func testPreviewTextJoinsSheetsWithHeaders() {
        let sheets: [(name: String, rows: [[String]])] = [
            (name: "Sheet 1", rows: [["a"]]),
            (name: "Sheet 2", rows: [["b"]])
        ]
        let text = SpreadsheetHTMLParser.previewText(sheets: sheets)
        XCTAssertEqual(text, "== Sheet 1 ==\na\n\n== Sheet 2 ==\nb")
    }
}
