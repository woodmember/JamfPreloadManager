import SwiftUI

struct DashboardView: View {
    let model: AppModel

    @State private var connectionDetails: String?
    @State private var alertMessage: String?
    @State private var isTesting = false
    @State private var isExporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppConstants.appName)
                        .font(.largeTitle.weight(.semibold))
                    Text("Version \(AppConstants.appVersion)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("A native macOS workspace for looking up, creating, updating, bulk uploading, exporting, and deleting Jamf inventory preload records.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox("Jamf Connection") {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Server") {
                            Text(model.configuration.serverURL)
                                .textSelection(.enabled)
                        }

                        LabeledContent("Client ID") {
                            Text(model.configuration.clientID.nilIfBlank ?? "Not saved")
                                .textSelection(.enabled)
                        }

                        LabeledContent("Status") {
                            Label(model.connectionState.title, systemImage: model.connectionState.systemImage)
                        }

                        Text(model.connectionState.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    isTesting = true
                                    connectionDetails = nil
                                    if let result = await model.testConnection() {
                                        connectionDetails = result.detailText
                                    }
                                    isTesting = false
                                }
                            } label: {
                                Label(isTesting ? "Testing..." : "Test Connection", systemImage: "bolt.horizontal.circle")
                            }
                            .disabled(isTesting || isExporting)

                            SettingsLink {
                                Label("Open Settings", systemImage: "gearshape")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Export Inventory Preload") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export a CSV containing all current devices with inventory preload data.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task {
                                isExporting = true
                                do {
                                    _ = try await model.exportCSV()
                                } catch {
                                    alertMessage = error.localizedDescription
                                }
                                isExporting = false
                            }
                        } label: {
                            Label(isExporting ? "Exporting Preload..." : "Export Inventory Preload", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isTesting || isExporting)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Connection Test Output") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let connectionDetails {
                            Text(connectionDetails)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Text("Run a connection test to verify the saved Jamf URL, credentials, token flow, and API access.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recent Activity")
                                .font(.headline)
                            Text(model.recentActivity)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                GroupBox("Workflow Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use Find Entry to inspect a serial without editing it.")
                        Text("Use Add Entry to create a new preload record with approved or custom tags.")
                        Text("Use Modify Entry to load an existing record, change its extension attributes, and save it back.")
                        Text("Use Bulk Update for CSV template downloads, Jamf CSV uploads, and bulk deletes.")
                        Text("Delete Entry is intentionally separated and framed as an admin-only task.")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .errorAlert($alertMessage)
    }
}
