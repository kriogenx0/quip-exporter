import SwiftUI

@main
struct QuipExporterApp: App {
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
