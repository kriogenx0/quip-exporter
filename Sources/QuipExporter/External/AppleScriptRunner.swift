import Foundation

enum AppleScriptRunner {
    static func run(_ script: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".applescript")
        try script.write(to: tmp, atomically: true, encoding: .utf8)

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
            saveFailedScript(script)
            try? FileManager.default.removeItem(at: tmp)
            throw NotesError.applescript(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try? FileManager.default.removeItem(at: tmp)
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Kept on disk (unlike the temp script, which is always deleted) so a failing run's
    // exact AppleScript source can be inspected afterward instead of only having
    // osascript's line:column error message to go on.
    private static func saveFailedScript(_ script: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuipExporter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? script.write(to: dir.appendingPathComponent("last-failed.applescript"), atomically: true, encoding: .utf8)
    }
}
