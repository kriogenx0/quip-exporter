import SwiftUI

@main
struct QuipExporterApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--test-note") {
            let writer = NotesWriter(account: "")
            do {
                let folderId = try writer.getOrCreateFolder(path: ["Quip Export"])
                let (sent, received) = try writer.runFormattingTest(folderId: folderId)
                print("── SENT HTML ──────────────────────────────────")
                print(sent)
                print("── RECEIVED HTML ──────────────────────────────")
                print(received)
            } catch {
                fputs("Error: \(error)\n", stderr)
            }
            exit(0)
        }

        if ProcessInfo.processInfo.arguments.contains("--markdown-import-test") {
            let writer = NotesWriter(account: "")
            do {
                let folderId = try writer.getOrCreateFolder(path: ["Quip Export"])
                let (markdown, received) = try writer.runMarkdownImportTest(folderId: folderId)
                print("── MARKDOWN SENT ──────────────────────────────")
                print(markdown)
                print("── RECEIVED HTML ──────────────────────────────")
                print(received)
            } catch {
                fputs("Error: \(error)\n", stderr)
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Quip Exporter") {
            ContentView()
        }
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
