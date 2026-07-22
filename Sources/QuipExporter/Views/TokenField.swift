import SwiftUI

struct TokenField: View {
    @Binding var text: String
    var isSecure: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .font(.system(.body, design: .monospaced))
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}
