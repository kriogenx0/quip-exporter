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
        try AppleScriptRunner.run(script)
    }

    // A regex-based replacement is best-effort throughout this file — Quip's HTML is
    // never guaranteed to match a given pattern, so a failed/non-matching regex should
    // leave the string untouched rather than throwing.
    private func regexReplace(_ pattern: String, in s: String, with template: String,
                              options: NSRegularExpression.Options = .caseInsensitive) -> String {
        (try? NSRegularExpression(pattern: pattern, options: options))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template) ?? s
    }

    // AppleScript snippet that loads the folder for later lines in the same `tell` block
    // to operate on — repeated across every script that reads or writes a note.
    private func loadFolderLine(_ folderId: String) -> String {
        "set theFolder to folder id \"\(esc(folderId))\" of \(accountRef)"
    }

    // AppleScript snippet that returns `onMatch` for the first note titled `title` in
    // theFolder whose body carries the "Created in Quip" marker for `createdStr`,
    // otherwise returns `whenNotFound` — shared by the read-only lookups (noteExists,
    // existingBody). updateNote needs the same match but also mutates on a hit, so it
    // isn't a drop-in user of this helper.
    private func findNoteScript(title: String, createdStr: String, onMatch: String, whenNotFound: String) -> String {
        """
        set matchNotes to every note of theFolder whose name is "\(esc(title))"
        repeat with n in matchNotes
            if body of n contains "Created in Quip: \(esc(createdStr))" then return \(onMatch)
        end repeat
        return \(whenNotFound)
        """
    }

    // Writes `content` to a throwaway temp file and returns the AppleScript line that
    // reads it back into `htmlContent` via `cat` — passing multi-KB HTML bodies as
    // inline AppleScript string literals is unreliable, so every note-body write goes
    // through a temp file instead. Caller is responsible for removing `url`.
    private func writeTempFile(_ content: String, extension ext: String) throws -> (url: URL, catLine: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(ext)")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        let catLine = "set htmlContent to do shell script \"cat \" & quoted form of \"\(tmp.path)\""
        return (tmp, catLine)
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
    \(loadFolderLine(folderId))
    \(findNoteScript(title: title, createdStr: createdStr, onMatch: "true", whenNotFound: "false"))
end tell
""") == "true"
    }

    // Returns the body of the existing note matched by noteExists' own criteria, for
    // diffing against the freshly-generated HTML before deciding whether to overwrite.
    func existingBody(title: String, folderId: String, createdStr: String) throws -> String? {
        let result = try run("""
tell application "Notes"
    \(loadFolderLine(folderId))
    \(findNoteScript(title: title, createdStr: createdStr, onMatch: "body of n", whenNotFound: "\"\""))
end tell
""")
        return result.isEmpty ? nil : result
    }

    @discardableResult
    func createNote(title: String, htmlBody: String, folderId: String) throws -> String {
        let (tmp, catLine) = try writeTempFile(htmlBody, extension: "html")
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try run("""
tell application "Notes"
    \(loadFolderLine(folderId))
    \(catLine)
    set theNote to make new note at theFolder with properties {body:htmlContent}
    return id of theNote
end tell
""")
    }

    // Replaces the body of the existing note matched by noteExists' own criteria
    // (same title, body containing the same "Created in Quip" marker).
    @discardableResult
    func updateNote(title: String, htmlBody: String, folderId: String, createdStr: String) throws -> String {
        let (tmp, catLine) = try writeTempFile(htmlBody, extension: "html")
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try run("""
tell application "Notes"
    \(loadFolderLine(folderId))
    \(catLine)
    set matchNotes to every note of theFolder whose name is "\(esc(title))"
    repeat with n in matchNotes
        if body of n contains "Created in Quip: \(esc(createdStr))" then
            set body of n to htmlContent
            return id of n
        end if
    end repeat
    set theNote to make new note at theFolder with properties {body:htmlContent}
    return id of theNote
end tell
""")
    }

    // Notes' scripting dictionary has no per-paragraph checklist API — the only way to
    // turn a line into a real checkbox item is to select it in the editor UI and trigger
    // Format > Checklist, via System Events. This is experimental: it requires granting
    // Notes/System Events Accessibility access (System Settings > Privacy & Security >
    // Accessibility), and relies on each item's text being unique enough within the note
    // to locate via a plain text search. Failures here are non-fatal to the caller.
    func applyChecklistFormatting(noteId: String, itemTexts: [String]) throws {
        guard !itemTexts.isEmpty else { return }
        let itemList = itemTexts.map { "\"\(esc($0))\"" }.joined(separator: ", ")
        _ = try run("""
tell application "Notes"
    activate
    show note id "\(esc(noteId))" of \(accountRef)
end tell
delay 0.4
tell application "System Events"
    tell process "Notes"
        set targetItems to {\(itemList)}
        repeat with itemText in targetItems
            try
                set noteArea to text area 1 of scroll area 1 of front window
                set fullText to (value of noteArea) as string
                set charOffset to offset of (itemText as string) in fullText
                if charOffset > 0 then
                    set value of attribute "AXSelectedTextRange" of noteArea to {charOffset - 1, length of (itemText as string)}
                    click menu item "Checklist" of menu "Format" of menu bar 1
                end if
            end try
        end repeat
    end tell
end tell
""")
    }

    func renameNote(oldTitle: String, newTitle: String, folderId: String) throws {
        _ = try run("""
tell application "Notes"
    \(loadFolderLine(folderId))
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
        let (tmp, catLine) = try writeTempFile(sent, extension: "html")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let noteId = try run("""
tell application "Notes"
    \(loadFolderLine(folderId))
    \(catLine)
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

    func buildHTML(html: String, noteTitle: String, createdStr: String, folderDisplay: String, quipLink: String) -> (html: String, checklistItems: [String]) {
        var body = html
        let (checklistHTML, checklistItems) = convertChecklists(body)
        body = checklistHTML
        body = convertDecimalLists(body)
        body = stripListNoise(body)
        body = numberOrderedLists(body)
        body = convertBlockquotes(body)
        body = normalizeHeadings(body)
        body = convertHorizontalRules(body)
        body = convertHighlights(body)
        let linkLine = quipLink.isEmpty ? "" :
            "<p><em>Quip Link: <a href=\"\(escHTML(quipLink))\">\(escHTML(quipLink))</a></em></p>"
        let fullHTML = "<html><head><style>li{margin:0;padding:0}li p{margin:0;padding:0}ul,ol{margin:0;padding:0 0 0 1.5em}</style></head><body>"
            + "<h1>\(escHTML(noteTitle))</h1>"
            + "<p><em>Created in Quip: \(createdStr)</em></p>"
            + "<p><em>From Quip Folder: \(escHTML(folderDisplay))</em></p>"
            + linkLine + "<hr/>" + body + "</body></html>"
        return (fullHTML, checklistItems)
    }

    // Apple Notes' body-setting API silently drops background-color spans (confirmed via
    // runFormattingTest's round trip), but foreground text color does survive — so a
    // Quip highlight is mirrored onto the text color as the closest visible substitute.
    private func convertHighlights(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<span([^>]*)style="([^"]*background-color:\s*(#[0-9a-fA-F]{3,8})[^"]*)"([^>]*)>"#,
            options: .caseInsensitive) else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let before = ns.substring(with: match.range(at: 1))
            let style = ns.substring(with: match.range(at: 2))
            let color = ns.substring(with: match.range(at: 3))
            let after = ns.substring(with: match.range(at: 4))
            let hasOwnColor = style.replacingOccurrences(of: "background-color", with: "").contains("color:")
            let newStyle = hasOwnColor ? style : "\(style);color:\(color)"
            result += "<span\(before)style=\"\(newStyle)\"\(after)>"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: - Checklist conversion

    // Returns the converted HTML plus the plain-text (with [x]/[ ] prefix) of every
    // checklist item, in document order — used as search needles by
    // applyChecklistFormatting to locate each line in the live Notes editor afterward.
    private func convertChecklists(_ html: String) -> (html: String, items: [String]) {
        var s = html
        // Tag Quip checklist <ul> elements for processing
        s = regexReplace(#"<ul[^>]*class="[^"]*\b(?:checklist|checkmark|list-check\w*|todo)\b[^"]*"[^>]*>"#,
                          in: s, with: "<ul data-quip-checklist>")
        // Tag checked <li> items
        s = regexReplace(#"<li[^>]*\bchecked\b[^>]*>"#, in: s, with: "<li data-quip-checked>")
        return applyCheckboxSymbols(s)
    }

    // Converts tagged checklist items to [x]/[ ] prefixed plain list items.
    private func applyCheckboxSymbols(_ html: String) -> (html: String, items: [String]) {
        let open = "<ul data-quip-checklist>"
        let close = "</ul>"
        var result = ""
        var items: [String] = []
        var remaining = html[...]
        while let r = remaining.range(of: open) {
            result += remaining[..<r.lowerBound]
            result += "<ul>"
            remaining = remaining[r.upperBound...]
            guard let c = remaining.range(of: close) else {
                result += remaining; return (result, items)
            }
            var inner = String(remaining[..<c.lowerBound])
            // Sentinel prevents checked items from being re-matched by the unchecked pass
            inner = inner.replacingOccurrences(of: "<li data-quip-checked>", with: "\u{02}")
            inner = regexReplace(#"<li[^>]*>"#, in: inner, with: "<li>[ ] ")
            inner = inner.replacingOccurrences(of: "\u{02}", with: "<li>[x] ")
            items.append(contentsOf: extractListItemTexts(inner))
            result += inner + close
            remaining = remaining[c.upperBound...]
        }
        result += remaining
        return (result, items)
    }

    // Strips HTML tags from each <li> to get the plain text Notes will actually display.
    private func extractListItemTexts(_ html: String) -> [String] {
        guard let liRegex = try? NSRegularExpression(
            pattern: #"<li[^>]*>(.*?)</li>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return liRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let inner = ns.substring(with: match.range(at: 1))
            let stripped = regexReplace("<[^>]+>", in: inner, with: "")
            let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
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
        s = regexReplace(#"(<li[^>]*>)\s*<p[^>]*>"#, in: s, with: "$1")
        s = regexReplace(#"</p>\s*</li>"#, in: s, with: "</li>")
        // Remove trailing <br> before </li> and any <br> between items
        s = regexReplace(#"<br\s*/?>\s*</li>"#, in: s, with: "</li>")
        s = regexReplace(#"</li>\s*(?:<br\s*/?>\s*)*<li"#, in: s, with: "</li><li")
        // Strip Quip-specific attributes from <ol> and <ul>
        s = regexReplace(#"<ol[^>]+>"#, in: s, with: "<ol>")
        s = regexReplace(#"<ul[^>]+>"#, in: s, with: "<ul>")
        // Merge consecutive <ul> and <ol> — handles both simple gaps and Quip's div-per-item wrapping
        s = regexReplace(#"</ul>\s*(?:</div>\s*<div[^>]*>\s*)?(?:<br\s*/?>\s*)*<ul>"#, in: s, with: "")
        s = regexReplace(#"</ol>\s*(?:</div>\s*<div[^>]*>\s*)?(?:<br\s*/?>\s*)*<ol>"#, in: s, with: "")
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
        regexReplace(#"<blockquote[^>]*>"#, in: html, with: #"<blockquote type="cite">"#)
    }

    private func normalizeHeadings(_ html: String) -> String {
        var s = html
        // Cap H4-H6 at H3 — Apple Notes only has Title (h1), Heading (h2), Subheading (h3)
        s = regexReplace(#"<h[4-6][^>]*>"#, in: s, with: "<h3>")
        s = regexReplace(#"</h[4-6]>"#, in: s, with: "</h3>")
        // Strip Quip-specific attributes — clean <h1>/<h2>/<h3> is required for Apple Notes to apply its styles
        s = regexReplace(#"<h([1-3])[^>]*>"#, in: s, with: "<h$1>")
        return s
    }

    private func convertHorizontalRules(_ html: String) -> String {
        let rule = "<p>——————————————————————————————</p>"
        // Match <hr> with any attributes or self-closing variants
        return regexReplace(#"<hr[^>]*/?>"#, in: html, with: rule)
    }

    private func escHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
