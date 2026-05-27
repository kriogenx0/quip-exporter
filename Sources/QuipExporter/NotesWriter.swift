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

    func noteExists(title: String, folderId: String) throws -> Bool {
        try run("""
tell application "Notes"
    set theFolder to folder id "\(esc(folderId))" of \(accountRef)
    return (count of (every note of theFolder whose name is "\(esc(title))")) > 0
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
}
