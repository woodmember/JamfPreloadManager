import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct JamfPreloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .appAppearance(resolvedAppearanceMode)
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    await model.loadConfiguration()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Appearance") {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearanceMode = mode.rawValue
                    } label: {
                        if resolvedAppearanceMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Reveal Activity Log in Finder") {
                    revealActivityLog()
                }
                Button("Open Activity Log") {
                    openActivityLog()
                }
            }
        }

        Settings {
            TabView {
                SettingsView(model: model)
                    .padding(24)
                    .tabItem {
                        Label("Server & Credentials", systemImage: "key")
                    }

                FieldSettingsView(model: model)
                    .padding(24)
                    .tabItem {
                        Label("Fields", systemImage: "list.bullet.rectangle")
                    }
            }
            .appAppearance(resolvedAppearanceMode)
            .frame(width: 720, height: 720)
        }
    }

    private var resolvedAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private func revealActivityLog() {
        guard let url = AuditLogger.shared.ensureLogFileExists() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openActivityLog() {
        guard let url = AuditLogger.shared.ensureLogFileExists() else { return }
        NSWorkspace.shared.open(url)
    }
}
