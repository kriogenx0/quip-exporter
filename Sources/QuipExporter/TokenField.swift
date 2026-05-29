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
    }
}
