import SwiftUI
import AppKit

// Selects all its text whenever it becomes first responder, so clicking anywhere in
// the field — not just double/triple-clicking — selects the whole token for easy
// copy/replace. Plain SwiftUI TextField/SecureField have no hook for this, hence the
// NSViewRepresentable bridge.
private final class SelectAllTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { self.currentEditor()?.selectAll(nil) }
        }
        return result
    }
}

private final class SelectAllSecureTextField: NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { self.currentEditor()?.selectAll(nil) }
        }
        return result
    }
}

struct TokenField: NSViewRepresentable {
    @Binding var text: String
    var isSecure: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? SelectAllSecureTextField() : SelectAllTextField()
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}
