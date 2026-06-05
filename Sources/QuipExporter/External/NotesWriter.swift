import Foundation

struct NotesWriter {
    let account: String

    private var accountRef: String {
        account.isEmpty ? "default account" : "account \"\(esc(account))\""
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func run(_ script: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".applescript")
        try script.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [tmp.path]
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NotesError.applescript(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findOrCreateSteps(path: [String]) -> String {
        var lines = [
            "set acct to \(accountRef)",
            "set parentObj to acct",
        ]
        for name in path {
            lines += [
                "set matchFolders to every folder of acct whose name is \"\(esc(name))\"",
                "set curFolder to missing value",
                "repeat with f in matchFolders",
                "    if container of f is parentObj then",
                "        set curFolder to f",
                "        exit repeat",
                "    end if",
                "end repeat",
                "if curFolder is missing value then",
                "    try",
                "        set curFolder to make new folder with properties {name:\"\(esc(name))\"} at parentObj",
                "    on error",
                "        set curFolder to first folder of acct whose name is \"\(esc(name))\"",
                "    end try",
                "end if",
                "set parentObj to curFolder",
            ]
        }
        lines.append("return id of curFolder")
        return lines.joined(separator: "\n    ")
    }

    func getOrCreateFolder(path: [String]) throws -> String {
        try run("""
tell application "Notes"
    \(findOrCreateSteps(path: path))
end tell
""")
    }

    func noteExists(title: String, folderId: String, createdStr: String) throws -> Bool {
        try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    set matchNotes to every note of theFolder whose name is "\(esc(title))"
    repeat with n in matchNotes
        if body of n contains "Created in Quip: \(esc(createdStr))" then return true
    end repeat
    return false
end tell
""") == "true"
    }

    func createNote(title: String, htmlBody: String, folderId: String) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".html")
        try htmlBody.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    set htmlContent to do shell script "cat " & quoted form of "\(tmp.path)"
    make new note at theFolder with properties {body:htmlContent}
end tell
""")
    }

    func renameNote(oldTitle: String, newTitle: String, folderId: String) throws {
        _ = try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    set theNote to first note of theFolder whose name is "\(esc(oldTitle))"
    set name of theNote to "\(esc(newTitle))"
end tell
""")
    }

    // Creates a diagnostic note with every formatting type, then reads it back.
    // Returns (sent HTML, received body HTML) so the caller can log both for comparison.
    func runFormattingTest(folderId: String) throws -> (sent: String, received: String) {
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let sent = Self.formattingTestHTML(dateStr: dateStr)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".html")
        try sent.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let noteId = try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    set htmlContent to do shell script "cat " & quoted form of "\(tmp.path)"
    set theNote to make new note at theFolder with properties {body:htmlContent}
    return id of theNote
end tell
""")
        Thread.sleep(forTimeInterval: 1.5)
        let received = try run("""
tell application "Notes"
    set theNote to note id "\(esc(noteId))" of \(accountRef)
    return body of theNote
end tell
""")
        return (sent: sent, received: received)
    }

    // Writes a Markdown file and imports it into Notes via the `import` command,
    // then reads back the body to see how Notes interpreted the Markdown.
    func runMarkdownImportTest(folderId: String) throws -> (markdown: String, received: String) {
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let title = "Markdown Import Test \u{2014} \(dateStr)"
        let markdown = Self.markdownTestContent(title: title)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        try markdown.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteId = try run("""
do shell script "open -a Notes " & quoted form of "\(tmp.path)"
delay 3
tell application "Notes"
    set matchNotes to every note of \(accountRef) whose name contains "\(esc(title))"
    if (count of matchNotes) > 0 then return id of item 1 of matchNotes
    return ""
end tell
""")
        guard !noteId.isEmpty else {
            throw NotesError.applescript("Note not found — Notes may not handle .md files")
        }
        Thread.sleep(forTimeInterval: 1.0)
        let received = try run("""
tell application "Notes"
    set theNote to note id "\(esc(noteId))" of \(accountRef)
    return body of theNote
end tell
""")
        return (markdown: markdown, received: received)
    }

    // MARK: - HTML building

    func buildHTML(html: String, noteTitle: String, createdStr: String, folderDisplay: String, quipLink: String) -> String {
        var body = html
        body = convertChecklists(body)
        body = convertDecimalLists(body)
        body = stripListNoise(body)
        body = numberOrderedLists(body)
        body = convertBlockquotes(body)
        body = normalizeHeadings(body)
        body = convertHorizontalRules(body)
        let linkLine = quipLink.isEmpty ? "" :
            "<p><em>Quip Link: <a href=\"\(escHTML(quipLink))\">\(escHTML(quipLink))</a></em></p>"
        return "<html><head><style>li{margin:0;padding:0}li p{margin:0;padding:0}ul,ol{margin:0;padding:0 0 0 1.5em}</style></head><body>"
            + "<h1>\(escHTML(noteTitle))</h1>"
            + "<p><em>Created in Quip: \(createdStr)</em></p>"
            + "<p><em>From Quip Folder: \(escHTML(folderDisplay))</em></p>"
            + linkLine + "<hr/>" + body + "</body></html>"
    }

    // MARK: - Checklist conversion

    private func convertChecklists(_ html: String) -> String {
        var s = html
        // Tag Quip checklist <ul> elements for processing
        s = (try? NSRegularExpression(
            pattern: #"<ul[^>]*class="[^"]*\b(?:checklist|checkmark|list-check\w*|todo)\b[^"]*"[^>]*>"#,
            options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                      withTemplate: "<ul data-quip-checklist>") ?? s
        // Tag checked <li> items
        s = (try? NSRegularExpression(pattern: #"<li[^>]*\bchecked\b[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                      withTemplate: "<li data-quip-checked>") ?? s
        return applyCheckboxSymbols(s)
    }

    // Converts tagged checklist items to [x]/[ ] prefixed plain list items.
    private func applyCheckboxSymbols(_ html: String) -> String {
        let open = "<ul data-quip-checklist>"
        let close = "</ul>"
        var result = ""
        var remaining = html[...]
        while let r = remaining.range(of: open) {
            result += remaining[..<r.lowerBound]
            result += "<ul>"
            remaining = remaining[r.upperBound...]
            guard let c = remaining.range(of: close) else {
                result += remaining; return result
            }
            var inner = String(remaining[..<c.lowerBound])
            // Sentinel prevents checked items from being re-matched by the unchecked pass
            inner = inner.replacingOccurrences(of: "<li data-quip-checked>", with: "\u{02}")
            inner = (try? NSRegularExpression(pattern: #"<li[^>]*>"#, options: .caseInsensitive))?
                .stringByReplacingMatches(in: inner, range: NSRange(inner.startIndex..., in: inner),
                                          withTemplate: "<li>[ ] ") ?? inner
            inner = inner.replacingOccurrences(of: "\u{02}", with: "<li>[x] ")
            result += inner + close
            remaining = remaining[c.upperBound...]
        }
        result += remaining
        return result
    }

    // MARK: - List conversion

    // Converts <ul class="list-decimal"> (Quip's numbered list format) to <ol>.
    private func convertDecimalLists(_ html: String) -> String {
        let openPattern = #"<ul[^>]*\blist-decimal\b[^>]*>"#
        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: .caseInsensitive) else { return html }
        var result = ""
        var pos = html.startIndex
        while pos < html.endIndex {
            guard let match = openRegex.firstMatch(in: html, range: NSRange(pos..<html.endIndex, in: html)),
                  let matchRange = Range(match.range, in: html) else {
                result += html[pos...]
                break
            }
            result += html[pos..<matchRange.lowerBound]
            result += "<ol>"
            pos = matchRange.upperBound
            if let closeRange = html.range(of: "</ul>", options: .caseInsensitive, range: pos..<html.endIndex) {
                result += html[pos..<closeRange.lowerBound]
                result += "</ol>"
                pos = closeRange.upperBound
            }
        }
        return result
    }

    private func stripListNoise(_ html: String) -> String {
        var s = html
        // Remove <p> wrappers inside <li>, preserving <li> attributes
        s = (try? NSRegularExpression(pattern: #"(<li[^>]*>)\s*<p[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1") ?? s
        s = (try? NSRegularExpression(pattern: #"</p>\s*</li>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "</li>") ?? s
        // Remove trailing <br> before </li> and any <br> between items
        s = (try? NSRegularExpression(pattern: #"<br\s*/?>\s*</li>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "</li>") ?? s
        s = (try? NSRegularExpression(pattern: #"</li>\s*(?:<br\s*/?>\s*)*<li"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "</li><li") ?? s
        // Strip Quip-specific attributes from <ol> and <ul>
        s = (try? NSRegularExpression(pattern: #"<ol[^>]+>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<ol>") ?? s
        s = (try? NSRegularExpression(pattern: #"<ul[^>]+>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<ul>") ?? s
        // Merge consecutive <ul> and <ol> — handles both simple gaps and Quip's div-per-item wrapping
        s = (try? NSRegularExpression(pattern: #"</ul>\s*(?:</div>\s*<div[^>]*>\s*)?(?:<br\s*/?>\s*)*<ul>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s
        s = (try? NSRegularExpression(pattern: #"</ol>\s*(?:</div>\s*<div[^>]*>\s*)?(?:<br\s*/?>\s*)*<ol>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s
        return s
    }

    // Converts <ol> blocks to manually-numbered <p> elements, since Apple Notes
    // may not render <ol> as a numbered list when set via AppleScript.
    private func numberOrderedLists(_ html: String) -> String {
        let open = "<ol>"
        let close = "</ol>"
        guard let liRegex = try? NSRegularExpression(
            pattern: #"<li[^>]*>(.*?)</li>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return html }
        var result = ""
        var pos = html.startIndex
        while pos < html.endIndex {
            guard let openRange = html.range(of: open, options: .caseInsensitive, range: pos..<html.endIndex) else {
                result += html[pos...]
                break
            }
            result += html[pos..<openRange.lowerBound]
            pos = openRange.upperBound
            guard let closeRange = html.range(of: close, options: .caseInsensitive, range: pos..<html.endIndex) else {
                result += html[pos...]
                break
            }
            let inner = String(html[pos..<closeRange.lowerBound])
            pos = closeRange.upperBound
            let matches = liRegex.matches(in: inner, range: NSRange(inner.startIndex..., in: inner))
            if matches.isEmpty {
                result += "<ol>" + inner + "</ol>"
            } else {
                for (i, match) in matches.enumerated() {
                    let content = Range(match.range(at: 1), in: inner).map { String(inner[$0]) } ?? ""
                    result += "<p>\(i + 1). \(content.trimmingCharacters(in: .whitespacesAndNewlines))</p>"
                }
            }
        }
        return result
    }

    // MARK: - Other element conversion

    // Uses <blockquote type="cite"> which Apple Notes / WebKit recognises as a quoted block.
    private func convertBlockquotes(_ html: String) -> String {
        return (try? NSRegularExpression(pattern: #"<blockquote[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html),
                                      withTemplate: #"<blockquote type="cite">"#) ?? html
    }

    private func normalizeHeadings(_ html: String) -> String {
        var s = html
        // Cap H4-H6 at H3 — Apple Notes only has Title (h1), Heading (h2), Subheading (h3)
        s = (try? NSRegularExpression(pattern: #"<h[4-6][^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<h3>") ?? s
        s = (try? NSRegularExpression(pattern: #"</h[4-6]>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "</h3>") ?? s
        // Strip Quip-specific attributes — clean <h1>/<h2>/<h3> is required for Apple Notes to apply its styles
        s = (try? NSRegularExpression(pattern: #"<h([1-3])[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "<h$1>") ?? s
        return s
    }

    private func convertHorizontalRules(_ html: String) -> String {
        let rule = "<p>——————————————————————————————</p>"
        // Match <hr> with any attributes or self-closing variants
        return (try? NSRegularExpression(pattern: #"<hr[^>]*/?>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html),
                                      withTemplate: rule) ?? html
    }

    private func escHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
