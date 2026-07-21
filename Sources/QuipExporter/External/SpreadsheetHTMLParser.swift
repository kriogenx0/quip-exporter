import Foundation

// Shared by NumbersWriter and CSVWriter: parses Quip spreadsheet HTML into per-tab
// rows of plain-text cells, and serializes rows as RFC 4180 CSV.
//
// Best-effort and unverified against a real Quip spreadsheet export (no sample HTML
// was available while building this). Treats every top-level <table> as one tab/sheet,
// named after an immediately preceding heading if present. rowspan is not handled;
// colspan is approximated by padding with blank cells.
struct SpreadsheetHTMLParser {
    static func parseSheets(fromHTML html: String) -> [(name: String, rows: [[String]])] {
        scanTags(["table"], in: html).enumerated().map { index, table in
            let name = sheetName(precedingHTML: table.precedingText) ?? "Sheet \(index + 1)"
            let rows = scanTags(["tr"], in: table.inner).map { row in
                scanTags(["td", "th"], in: row.inner).flatMap { cell -> [String] in
                    let text = plainText(fromHTML: cell.inner)
                    let span = max(1, colspan(fromAttrs: cell.attrs))
                    return [text] + Array(repeating: "", count: span - 1)
                }
            }
            return (name: name, rows: rows)
        }
    }

    static func csv(rows: [[String]]) -> String {
        rows.map { row in row.map(csvField).joined(separator: ",") }.joined(separator: "\r\n")
    }

    // A single text blob covering every sheet — used to preview/diff what CSVWriter or
    // NumbersWriter is about to write, since both ultimately export the same per-tab data.
    static func previewText(sheets: [(name: String, rows: [[String]])]) -> String {
        sheets.map { sheet in "== \(sheet.name) ==\n\(csv(rows: sheet.rows))" }.joined(separator: "\n\n")
    }

    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private struct TagMatch {
        let tag: String
        let attrs: String
        let inner: String
        let precedingText: String
    }

    // Scans for non-overlapping `<tag ...>...</tag>` blocks (first match wins among `tags`
    // at each position), left to right. Doesn't track nesting of the same tag name, which
    // matches how the other writers' regex-based HTML transforms already treat this HTML.
    private static func scanTags(_ tags: [String], in html: String) -> [TagMatch] {
        var results: [TagMatch] = []
        var searchStart = html.startIndex
        var blockStart = html.startIndex
        while let open = nextOpenTag(tags, in: html, from: searchStart),
              let tagEnd = html.range(of: ">", range: open.nameEnd..<html.endIndex),
              let closeRange = html.range(of: "</\(open.tag)>", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex) {
            let attrs = String(html[open.nameEnd..<tagEnd.lowerBound])
            let inner = String(html[tagEnd.upperBound..<closeRange.lowerBound])
            let precedingText = String(html[blockStart..<open.start])
            results.append(TagMatch(tag: open.tag, attrs: attrs, inner: inner, precedingText: precedingText))
            searchStart = closeRange.upperBound
            blockStart = closeRange.upperBound
        }
        return results
    }

    private static func nextOpenTag(_ tags: [String], in html: String, from start: String.Index) -> (tag: String, nameEnd: String.Index, start: String.Index)? {
        var best: (tag: String, nameEnd: String.Index, start: String.Index)?
        for tag in tags {
            var searchFrom = start
            while let r = html.range(of: "<\(tag)", options: .caseInsensitive, range: searchFrom..<html.endIndex) {
                let after = r.upperBound
                if after == html.endIndex || " \t\n\r/>".contains(html[after]) {
                    if best == nil || r.lowerBound < best!.start {
                        best = (tag: tag, nameEnd: after, start: r.lowerBound)
                    }
                    break
                }
                searchFrom = r.upperBound
            }
        }
        return best
    }

    private static func colspan(fromAttrs attrs: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"colspan\s*=\s*"?(\d+)"?"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range(at: 1), in: attrs) else { return 1 }
        return Int(attrs[range]) ?? 1
    }

    private static func sheetName(precedingHTML: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h[1-6][^>]*>(.*?)</h[1-6]>\s*$"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = precedingHTML as NSString
        guard let match = regex.firstMatch(in: precedingHTML, range: NSRange(location: 0, length: ns.length)),
              let range = Range(match.range(at: 1), in: precedingHTML) else { return nil }
        let text = plainText(fromHTML: String(precedingHTML[range]))
        return text.isEmpty ? nil : text
    }

    private static func plainText(fromHTML html: String) -> String {
        var s = (try? NSRegularExpression(pattern: #"<[^>]+>"#))?
            .stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: " ") ?? html
        s = s.replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&lt;", with: "<")
             .replacingOccurrences(of: "&gt;", with: ">")
             .replacingOccurrences(of: "&quot;", with: "\"")
             .replacingOccurrences(of: "&#39;", with: "'")
             .replacingOccurrences(of: "&nbsp;", with: " ")
        s = (try? NSRegularExpression(pattern: #"\s+"#))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ") ?? s
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
