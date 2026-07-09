import SwiftUI

struct SettingsView: View {
    let model: AppModel

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @State private var selectedServerURL = ""
    @State private var newServerURL = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var feedback = "Saved settings are stored in your login keychain."
    @State private var connectionDetails: String?
    @State private var alertMessage: String?
    @State private var isAddingServer = false
    @State private var isSwitchingServer = false
    @State private var isSaving = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle.weight(.semibold))

            Form {
                Section("Saved Servers") {
                    Picker("Active Server", selection: $selectedServerURL) {
                        ForEach(model.savedServerURLs, id: \.self) { serverURL in
                            Text(serverURL).tag(serverURL)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isBusy || model.savedServerURLs.isEmpty)
                    .onChange(of: selectedServerURL, initial: false) { _, newValue in
                        guard newValue != model.configuration.serverURL else {
                            return
                        }

                        switchServer(to: newValue)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        TextField("https://yourorg.jamfcloud.com", text: $newServerURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBusy)

                        Button {
                            addServer()
                        } label: {
                            Label(isAddingServer ? "Adding..." : "Add Server", systemImage: "plus")
                        }
                        .disabled(isBusy || newServerURL.trimmed.isEmpty)
                    }

                    Text("Switching servers reloads that host's saved keychain credentials into the app. Adding a server checks the keychain first, so existing credentials are picked up automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("API Credentials") {
                    TextField("Server URL", text: .constant(model.configuration.serverURL))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    TextField("Client ID", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isBusy)

                    SecureField("New Client Secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isBusy)

                    Text(credentialsHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: resolvedAppearanceMode.systemImage)
                            .font(.title2)
                            .frame(width: 28)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(resolvedAppearanceMode.title)
                                .font(.headline)

                            Text(resolvedAppearanceMode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Changes apply immediately to every Jamf Preload Manager window.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Actions") {
                    HStack {
                        Button {
                            saveSettings(runConnectionTest: false)
                        } label: {
                            Label(isSaving ? "Saving..." : "Save Credentials", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isBusy)

                        Button {
                            saveSettings(runConnectionTest: true)
                        } label: {
                            Label(isTesting ? "Testing..." : "Save & Test", systemImage: "bolt.horizontal.circle")
                        }
                        .disabled(isBusy)
                    }

                    Text(feedback)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            GroupBox("Connection Test Output") {
                if let connectionDetails {
                    Text(connectionDetails)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text("Use Save & Test to verify the current Jamf server and credentials.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: model.configuration, initial: true) { _, _ in
            syncFromModel()
        }
        .errorAlert($alertMessage)
    }

    private func syncFromModel() {
        selectedServerURL = model.configuration.serverURL
        // Seed the Client ID from a managed default when nothing is stored yet.
        // This is only a starting point — the user can still change it.
        clientID = model.configuration.clientID.nilIfBlank ?? model.managedDefaultClientID ?? ""
        clientSecret = ""
    }

    private func saveSettings(runConnectionTest: Bool) {
        Task {
            isSaving = true

            do {
                feedback = try await model.saveConfiguration(
                    serverURL: selectedServerURL,
                    clientID: clientID,
                    clientSecret: clientSecret.nilIfBlank
                )
                clientSecret = ""

                if runConnectionTest {
                    isTesting = true
                    if let result = await model.testConnection() {
                        connectionDetails = result.detailText
                    }
                    isTesting = false
                }
            } catch {
                alertMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func addServer() {
        let urlToAdd = newServerURL

        Task {
            isAddingServer = true
            connectionDetails = nil

            do {
                feedback = try await model.addServer(serverURL: urlToAdd)
                newServerURL = ""
            } catch {
                alertMessage = error.localizedDescription
            }

            isAddingServer = false
        }
    }

    private func switchServer(to serverURL: String) {
        Task {
            isSwitchingServer = true
            connectionDetails = nil

            do {
                feedback = try await model.switchServer(to: serverURL)
            } catch {
                selectedServerURL = model.configuration.serverURL
                alertMessage = error.localizedDescription
            }

            isSwitchingServer = false
        }
    }

    private var resolvedAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    private var credentialsHelpText: String {
        switch (
            model.configuration.clientID.trimmed.isEmpty,
            model.configuration.clientSecret.trimmed.isEmpty
        ) {
        case (false, false):
            "Credentials are already stored in the keychain for this server. Leave the secret blank to keep the current value."
        case (false, true):
            "A Client ID was found for this server, but the Client Secret is missing. Enter a new secret to finish configuring it."
        case (true, false):
            "A Client Secret exists for this server, but no Client ID was found. Enter the Client ID and save to repair the keychain entry."
        case (true, true):
            "No credentials are currently stored for this server. Enter them here to save them into the login keychain."
        }
    }

    private var isBusy: Bool {
        isAddingServer || isSwitchingServer || isSaving || isTesting
    }

}
