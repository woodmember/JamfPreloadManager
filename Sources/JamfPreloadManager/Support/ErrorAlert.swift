import SwiftUI

extension View {
    /// Presents a single OK alert whenever `message` is non-nil, clearing it on dismiss.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Jamf Preload Manager", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if $0 == false { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
