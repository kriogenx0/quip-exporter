import SwiftUI
import AppKit

struct LogView: NSViewRepresentable {
    let entries: [LogEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }

        let lastCount = context.coordinator.renderedCount
        guard entries.count > lastCount else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let newEntries = entries[lastCount...]
        let attrString = NSMutableAttributedString()

        for (i, entry) in newEntries.enumerated() {
            if lastCount > 0 || i > 0 {
                attrString.append(NSAttributedString(string: "\n"))
            }

            let ts = entry.timestamp.formatted(date: .omitted, time: .standard)
            attrString.append(NSAttributedString(string: ts + "  ", attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))

            let msgColor: NSColor = switch entry.level {
                case .info:    .labelColor
                case .warning: .systemOrange
                case .error:   .systemRed
            }
            attrString.append(NSAttributedString(string: entry.message, attributes: [
                .font: font,
                .foregroundColor: msgColor
            ]))
        }

        storage.append(attrString)
        context.coordinator.renderedCount = entries.count
        textView.scrollToEndOfDocument(nil)
    }

    class Coordinator {
        var renderedCount = 0
    }
}
