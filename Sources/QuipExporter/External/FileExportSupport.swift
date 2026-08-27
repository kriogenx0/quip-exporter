import Foundation

// Shared by every folder-based writer (Markdown/HTML/CSV/Numbers): filename sanitizing,
// nested output-folder creation, and blob-to-asset-file saving are identical regardless
// of which format is ultimately written.
enum FileExportSupport {
    static func sanitize(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Drops the first path component ("Quip Export") — that's the root output dir.
    static func ensureFolder(path: [String], in outputDir: URL) throws -> URL {
        let dir = path.dropFirst().reduce(outputDir) { $0.appendingPathComponent(sanitize($1)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Saves blob data to _assets/<hash>.<ext> inside dir, returns the relative path used
    // to reference it from the writer's own content (Markdown image ref, <img src>, etc).
    static func saveImage(data: Data, blobHash: String, dir: URL) throws -> String {
        let assetsDir = dir.appendingPathComponent("_assets")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let ext = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
        let file = assetsDir.appendingPathComponent("\(blobHash).\(ext)")
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file)
        }
        return "_assets/\(blobHash).\(ext)"
    }
}
