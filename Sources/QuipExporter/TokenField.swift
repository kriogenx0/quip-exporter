import SwiftUI
import AppKit

struct TokenField: NSViewRepresentable {
    @Binding var text: String
    var isSecure: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.font = Self.monoFont
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let currentlySecure = field.cell is NSSecureTextFieldCell
        if isSecure != currentlySecure {
            let cell: NSTextFieldCell = isSecure ? NSSecureTextFieldCell() : NSTextFieldCell()
            cell.isEditable = true
            cell.isSelectable = true
            cell.bezelStyle = .roundedBezel
            cell.isBezeled = true
            cell.font = Self.monoFont
            cell.stringValue = text
            field.cell = cell
            field.font = Self.monoFont
            field.delegate = context.coordinator
        }
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TokenField
        init(_ parent: TokenField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
