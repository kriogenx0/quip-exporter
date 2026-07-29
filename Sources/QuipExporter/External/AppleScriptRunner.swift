import Foundation

enum AppleScriptRunner {
    // Without a timeout, a stuck script (e.g. a target app blocked on a modal dialog
    // no one can click, such as iWork's "Where do you want to save this document?"
    // sheet) hangs the whole migration run forever and leaves its document open —
    // and every retry piles on another one. 3 minutes is generous for any single
    // AppleScript call this app makes, including a large spreadsheet's worth of cells.
    static func run(_ script: String, timeout: TimeInterval = 180) throws -> String {
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

        let exited = DispatchGroup()
        exited.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            exited.leave()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            saveFailedScript(script)
            try? FileManager.default.removeItem(at: tmp)
            throw NotesError.applescript("Timed out after \(Int(timeout))s waiting for a response — check for a dialog the app can't dismiss on its own.")
        }

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
