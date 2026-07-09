import AppKit
import SwiftUI

enum AppAppearanceController {
    @MainActor
    static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}

private struct AppAppearanceModifier: ViewModifier {
    let mode: AppearanceMode

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(mode.colorScheme)
            .onChange(of: mode, initial: true) { _, newMode in
                AppAppearanceController.apply(newMode)
            }
    }
}

extension View {
    func appAppearance(_ mode: AppearanceMode) -> some View {
        modifier(AppAppearanceModifier(mode: mode))
    }
}
