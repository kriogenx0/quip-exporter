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

    // Generates AppleScript that walks `path` level-by-level using the container
    // property so nested folders with duplicate names resolve correctly.
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
        _ = try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    make new note at theFolder with properties {body:"\(esc(htmlBody))"}
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

    func buildHTML(html: String, noteTitle: String, createdStr: String, folderDisplay: String, quipLink: String) -> String {
        var body = html
        body = convertChecklists(body)
        body = stripListNoise(body)
        body = addHeadingBreaks(body)
        let linkLine = quipLink.isEmpty ? "" :
            "<p><em>Quip Link: <a href=\"\(escHTML(quipLink))\">\(escHTML(quipLink))</a></em></p>"
        return "<html><head><style>li{margin:0;padding:0}li p{margin:0;padding:0}ul,ol{margin:0;padding:0 0 0 1.5em}</style></head><body>"
            + "<h1>\(escHTML(noteTitle))</h1>"
            + "<p><em>Created in Quip: \(createdStr)</em></p>"
            + "<p><em>From Quip Folder: \(escHTML(folderDisplay))</em></p>"
            + linkLine + "<hr/>" + body + "</body></html>"
    }

    // Converts Quip checklist <ul> elements to Apple Notes checklist format.
    private func convertChecklists(_ html: String) -> String {
        var s = html
        s = (try? NSRegularExpression(
            pattern: #"<ul[^>]*class="[^"]*\b(?:checklist|checkmark|list-check\w*|todo)\b[^"]*"[^>]*>"#,
            options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                      withTemplate: #"<ul class="Apple-Note-Checklist-List">"#) ?? s
        s = (try? NSRegularExpression(pattern: #"<li[^>]*\bchecked\b[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                      withTemplate: #"<li class="Apple-Note-Checklist-List-Item-Checked">"#) ?? s
        return markUncheckedChecklistItems(s)
    }

    // Scans for Apple Notes checklist <ul> blocks and converts any unconverted <li> to unchecked.
    private func markUncheckedChecklistItems(_ html: String) -> String {
        let open = #"<ul class="Apple-Note-Checklist-List">"#
        let close = "</ul>"
        var result = ""
        var remaining = html[...]
        while let r = remaining.range(of: open, options: .caseInsensitive) {
            result += remaining[..<r.lowerBound]
            result += open
            remaining = remaining[r.upperBound...]
            guard let c = remaining.range(of: close, options: .caseInsensitive) else {
                result += remaining; return result
            }
            var inner = String(remaining[..<c.lowerBound])
            inner = (try? NSRegularExpression(
                pattern: #"<li(?![^>]*Apple-Note-Checklist-List-Item)[^>]*>"#,
                options: .caseInsensitive))?
                .stringByReplacingMatches(in: inner, range: NSRange(inner.startIndex..., in: inner),
                                          withTemplate: #"<li class="Apple-Note-Checklist-List-Item-Unchecked">"#) ?? inner
            result += inner + close
            remaining = remaining[c.upperBound...]
        }
        result += remaining
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
        // Merge consecutive regular <ul> blocks (Quip wraps each bullet item in its own <ul>)
        s = (try? NSRegularExpression(pattern: #"</ul>\s*<ul(?![^>]*Apple-Note-Checklist)[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s
        // Merge consecutive Apple Notes checklist <ul> blocks
        s = (try? NSRegularExpression(pattern: #"</ul>\s*<ul class="Apple-Note-Checklist-List">"#))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s
        s = (try? NSRegularExpression(pattern: #"</ol>\s*<ol[^>]*>"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s
        return s
    }

    private func addHeadingBreaks(_ html: String) -> String {
        return (try? NSRegularExpression(pattern: #"(<h[1-6][^>]*>)"#, options: .caseInsensitive))?
            .stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html),
                                      withTemplate: "<br>$1") ?? html
    }

    private func escHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
