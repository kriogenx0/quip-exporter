import Foundation

struct HTMLWriter {
    let outputDir: URL

    func ensureFolder(path: [String]) throws -> URL {
        let dir = path.dropFirst().reduce(outputDir) { $0.appendingPathComponent(sanitize($1)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    private func escAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
