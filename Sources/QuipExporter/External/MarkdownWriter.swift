import Foundation

struct MarkdownWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        // Drop the first component ("Quip Export") — that's the root output dir
        let dir = path.dropFirst().reduce(outputDir) { $0.appendingPathComponent(sanitize($1)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func noteExists(title: String, dir: URL, createdStr: String) -> Bool {
        let file = dir.appendingPathComponent(sanitize(title) + ".md")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return content.hasPrefix("---") && content.contains("\ncreated: \(createdStr)\n")
    }

    func buildContent(title: String, html: String, quipLink: String, createdStr: String, folderPath: [String]) -> String {
        let markdown = htmlToMarkdown(html)
        let folderDisplay = folderPath.dropFirst().joined(separator: " / ")

        var front = "---\ntitle: \"\(title)\"\ncreated: \(createdStr)\n"
        if !folderDisplay.isEmpty { front += "quip_folder: \"\(folderDisplay)\"\n" }
        if !quipLink.isEmpty { front += "quip_link: \"\(quipLink)\"\n" }
        front += "---\n\n"

        return front + markdown
    }

    func writeContent(_ content: String, title: String, dir: URL) throws {
        let file = dir.appendingPathComponent(sanitize(title) + ".md")
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    func existingContent(title: String, dir: URL) -> String? {
        let file = dir.appendingPathComponent(sanitize(title) + ".md")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        let content = buildContent(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeContent(content, title: title, dir: dir)
    }

    // Saves blob data to _assets/<hash>.<ext> inside dir, returns relative markdown image ref.
    func saveImage(data: Data, blobHash: String, dir: URL) throws -> String {
        let assetsDir = dir.appendingPathComponent("_assets")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let ext = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let file = assetsDir.appendingPathComponent("\(blobHash).\(ext)")
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file)
        }
        return "_assets/\(blobHash).\(ext)"
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Basic HTML → Markdown converter for Quip-generated HTML.
    func htmlToMarkdown(_ html: String) -> String {
        var s = html

        // Block elements — process before stripping tags
        let blocks: [(String, String)] = [
            (#"<h1[^>]*>(.*?)</h1>"#, "# $1"),
            (#"<h2[^>]*>(.*?)</h2>"#, "## $1"),
            (#"<h3[^>]*>(.*?)</h3>"#, "### $1"),
            (#"<h4[^>]*>(.*?)</h4>"#, "#### $1"),
            (#"<h5[^>]*>(.*?)</h5>"#, "##### $1"),
            (#"<h6[^>]*>(.*?)</h6>"#, "###### $1"),
            (#"<li[^>]*>(.*?)</li>"#, "- $1"),
            (#"<p[^>]*>(.*?)</p>"#, "$1\n"),
            (#"<br\s*/?>"#, "\n"),
            (#"<hr\s*/?>"#, "\n---\n"),
            (#"<pre[^>]*><code[^>]*>(.*?)</code></pre>"#, "```\n$1\n```"),
        ]
        let opts: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
        for (pattern, template) in blocks {
            s = (try? NSRegularExpression(pattern: pattern, options: opts))?
                .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template) ?? s
        }

        // Inline elements
        let inlines: [(String, String)] = [
            (#"<strong[^>]*>(.*?)</strong>"#, "**$1**"),
            (#"<b[^>]*>(.*?)</b>"#, "**$1**"),
            (#"<em[^>]*>(.*?)</em>"#, "*$1*"),
            (#"<i[^>]*>(.*?)</i>"#, "*$1*"),
            (#"<code[^>]*>(.*?)</code>"#, "`$1`"),
            (#"<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, "[$2]($1)"),
            (#"<img[^>]*src="([^"]*)"[^>]*/>"#, "![]($1)"),
            (#"<img[^>]*src="([^"]*)"[^>]*>"#, "![]($1)"),
        ]
        for (pattern, template) in inlines {
            s = (try? NSRegularExpression(pattern: pattern, options: opts))?
                .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template) ?? s
        }

        // Strip remaining tags
        s = (try? NSRegularExpression(pattern: #"<[^>]+>"#))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "") ?? s

        // Decode HTML entities
        s = s.replacingOccurrences(of: "&amp;", with: "&")
             .replacingOccurrences(of: "&lt;", with: "<")
             .replacingOccurrences(of: "&gt;", with: ">")
             .replacingOccurrences(of: "&quot;", with: "\"")
             .replacingOccurrences(of: "&#39;", with: "'")
             .replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse excessive blank lines
        s = (try? NSRegularExpression(pattern: #"\n{3,}"#))?
            .stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n") ?? s

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
