import Foundation

struct HTMLWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        try FileExportSupport.ensureFolder(path: path, in: outputDir)
    }

    func noteExists(title: String, dir: URL, createdStr: String) -> Bool {
        let file = dir.appendingPathComponent(sanitize(title) + ".html")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return content.contains("content=\"\(createdStr)\"")
    }

    func buildContent(title: String, html: String, quipLink: String, createdStr: String, folderPath: [String]) -> String {
        let folderDisplay = folderPath.dropFirst().joined(separator: " / ")
        var head = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"UTF-8\">\n"
        head += "<meta name=\"created\" content=\"\(escAttr(createdStr))\">\n"
        if !folderDisplay.isEmpty {
            head += "<meta name=\"quip-folder\" content=\"\(escAttr(folderDisplay))\">\n"
        }
        if !quipLink.isEmpty {
            head += "<meta name=\"quip-link\" content=\"\(escAttr(quipLink))\">\n"
        }
        head += "<title>\(escAttr(title))</title>\n</head>\n<body>\n"
        return head + html + "\n</body>\n</html>"
    }

    func writeContent(_ content: String, title: String, dir: URL) throws {
        let file = dir.appendingPathComponent(sanitize(title) + ".html")
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    func existingContent(title: String, dir: URL) -> String? {
        let file = dir.appendingPathComponent(sanitize(title) + ".html")
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func writeNote(title: String, html: String, dir: URL, quipLink: String, createdStr: String, folderPath: [String]) throws {
        let content = buildContent(title: title, html: html, quipLink: quipLink, createdStr: createdStr, folderPath: folderPath)
        try writeContent(content, title: title, dir: dir)
    }

    func saveImage(data: Data, blobHash: String, dir: URL) throws -> String {
        try FileExportSupport.saveImage(data: data, blobHash: blobHash, dir: dir)
    }

    private func sanitize(_ name: String) -> String {
        FileExportSupport.sanitize(name)
    }

    private func escAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
