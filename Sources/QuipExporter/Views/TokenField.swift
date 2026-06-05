import SwiftUI

struct TokenField: View {
    @Binding var text: String
    var isSecure: Bool

    var body: some View {
        if isSecure {
            SecureField("", text: $text)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
        } else {
            TextField("", text: $text)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
        }
    }
}
