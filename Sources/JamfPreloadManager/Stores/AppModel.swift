import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var configuration = JamfConfiguration()
    var savedServerURLs = [AppConstants.defaultJamfURL]
    var selectedSection: AppSection? = .dashboard
    var connectionState: ConnectionState = .needsConfiguration
    var recentActivity = "Open Settings to load your Jamf server and API credentials."
    var isBootstrapping = true
    var fieldConfiguration = FieldConfiguration.neutralDefault
    var isFieldConfigurationManaged = false
    var managedDefaultServerURL: String?
    var managedDefaultClientID: String?

    private let configurationStore: JamfConfigurationStore
    private let settingsStore: AppSettingsStore

    init(
        configurationStore: JamfConfigurationStore = JamfConfigurationStore(
            keychain: KeychainStore(service: AppConstants.keychainService),
            legacyKeychain: KeychainStore(service: AppConstants.legacyKeychainService)
        ),
        settingsStore: AppSettingsStore = AppSettingsStore()
    ) {
        self.configurationStore = configurationStore
        self.settingsStore = settingsStore
    }

    func loadFieldConfiguration() {
        let snapshot = settingsStore.load()
        fieldConfiguration = snapshot.configuration
        isFieldConfigurationManaged = snapshot.isManaged
        managedDefaultServerURL = settingsStore.managedDefaultServerURL()
        managedDefaultClientID = settingsStore.managedDefaultClientID()
    }

    func saveFieldConfiguration(_ configuration: FieldConfiguration) throws {
        try settingsStore.save(configuration)
        let snapshot = settingsStore.load()
        fieldConfiguration = snapshot.configuration
        isFieldConfigurationManaged = snapshot.isManaged
    }

    func loadConfiguration() async {
        guard isBootstrapping else {
            return
        }

        loadFieldConfiguration()

        let store = configurationStore

        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try store.load()
            }.value

            apply(snapshot)

            if snapshot.configuration.isComplete {
                recentActivity = "Ready to manage inventory preload for \(snapshot.configuration.hostKey)."
            } else {
                recentActivity = "Open Settings to add the Jamf URL, Client ID, and Client Secret."
            }
        } catch {
            connectionState = .failed(error.localizedDescription)
            recentActivity = error.localizedDescription
        }

        isBootstrapping = false
    }

    func saveConfiguration(serverURL: String, clientID: String, clientSecret: String?) async throws -> String {
        let existingConfiguration = configuration
        let store = configurationStore

        let snapshot = try await Task.detached(priority: .userInitiated) {
            try store.save(
                serverURL: serverURL,
                clientID: clientID,
                clientSecret: clientSecret,
                existingConfiguration: existingConfiguration
            )
        }.value

        apply(snapshot)
        recentActivity = "Saved Jamf settings for \(snapshot.configuration.hostKey)."
        return recentActivity
    }

    func addServer(serverURL: String) async throws -> String {
        let store = configurationStore

        let snapshot = try await Task.detached(priority: .userInitiated) {
            try store.addServer(serverURL: serverURL)
        }.value

        apply(snapshot)

        if snapshot.configuration.hasCredentials {
            recentActivity = "Added \(snapshot.configuration.hostKey) and loaded saved credentials from the keychain."
        } else {
            recentActivity = "Added \(snapshot.configuration.hostKey). No stored credentials were found, so enter them in Settings."
        }

        return recentActivity
    }

    func switchServer(to serverURL: String) async throws -> String {
        let store = configurationStore

        let snapshot = try await Task.detached(priority: .userInitiated) {
            try store.switchServer(to: serverURL)
        }.value

        apply(snapshot)

        if snapshot.configuration.hasCredentials {
            recentActivity = "Switched to \(snapshot.configuration.hostKey) and loaded saved credentials from the keychain."
        } else {
            recentActivity = "Switched to \(snapshot.configuration.hostKey). No stored credentials were found for this server."
        }

        return recentActivity
    }

    func testConnection() async -> ConnectionTestResult? {
        guard let client = try? makeClient() else {
            connectionState = .needsConfiguration
            recentActivity = "Save a valid Jamf server URL and credentials before testing the connection."
            return nil
        }

        connectionState = .testing
        recentActivity = "Testing authentication and API access for \(configuration.hostKey)..."

        let result = await client.testConnection(storedServerURL: configuration.serverURL.nilIfBlank)

        if result.apiStatus.hasPrefix("SUCCESS") {
            connectionState = .connected("Authenticated against \(configuration.hostKey).")
        } else {
            connectionState = .failed(result.apiStatus)
        }

        recentActivity = "Connection test completed for \(configuration.hostKey)."
        return result
    }

    func findRecord(serial: String) async throws -> PreloadRecord? {
        let client = try makeClient()
        let record = try await client.fetchRecord(serial: serial)
        if let record {
            recentActivity = "Loaded preload record #\(record.id) for serial \(record.serialNumber)."
        } else {
            recentActivity = "No preload record was found for \(serial.uppercased().removingAllWhitespace)."
        }
        return record
    }

    func createRecord(from draft: PreloadDraft) async throws -> PreloadRecord {
        let client = try makeClient()
        let submission = try draft.validatedSubmission(configuration: fieldConfiguration)
        let record = try await client.createRecord(from: submission)
        AuditLogger.shared.logAdd(record)
        recentActivity = "Created preload record #\(record.id) for serial \(record.serialNumber)."
        return record
    }

    /// - Parameter previous: the record's state before this change, captured so the
    ///   audit log can record the old values for recovery.
    func updateRecord(id: Int, from draft: PreloadDraft, previous: PreloadRecord? = nil) async throws -> PreloadRecord {
        let client = try makeClient()
        let submission = try draft.validatedSubmission(configuration: fieldConfiguration)
        let record = try await client.updateRecord(id: id, submission: submission)
        AuditLogger.shared.logModify(before: previous, after: record)
        recentActivity = "Updated preload record #\(record.id) for serial \(record.serialNumber)."
        return record
    }

    func deleteRecord(_ record: PreloadRecord) async throws {
        let client = try makeClient()
        try await client.deleteRecord(id: record.id)
        AuditLogger.shared.logDelete(record)
        recentActivity = "Deleted preload record #\(record.id) for serial \(record.serialNumber)."
    }

    func bulkDeleteRecords(importedSerials: ImportedSerialList) async throws -> BulkOperationReport {
        _ = try configuration.validated()

        let serialNumbers = importedSerials.serialNumbers
        guard serialNumbers.isEmpty == false else {
            throw JamfAppError.validation("Import a CSV with at least one serial number before running bulk delete.")
        }

        return await runBulkOperation(kind: .delete, sourceName: importedSerials.sourceName, items: serialNumbers, serial: { $0 }) { serialNumber in
            guard let existingRecord = try await self.findRecord(serial: serialNumber) else {
                return (.skipped, "No preload record was found.")
            }
            try await self.deleteRecord(existingRecord)
            return (.success, "Deleted record #\(existingRecord.id).")
        }
    }

    func bulkUploadRecords(from draft: PreloadDraft, importedSerials: ImportedSerialList) async throws -> BulkOperationReport {
        _ = try configuration.validated()

        let serialNumbers = importedSerials.serialNumbers
        guard serialNumbers.isEmpty == false else {
            throw JamfAppError.validation("Import a CSV with at least one serial number before running bulk import.")
        }

        return await runBulkOperation(kind: .upload, sourceName: importedSerials.sourceName, items: serialNumbers, serial: { $0 }) { serialNumber in
            var rowDraft = draft
            rowDraft.serialNumber = serialNumber
            if let existingRecord = try await self.findRecord(serial: serialNumber) {
                let record = try await self.updateRecord(id: existingRecord.id, from: rowDraft, previous: existingRecord)
                return (.success, "Updated record #\(record.id).")
            } else {
                let record = try await self.createRecord(from: rowDraft)
                return (.success, "Created record #\(record.id).")
            }
        }
    }

    func bulkUploadRecords(csvFile: ImportedBulkCSVFile) async throws -> BulkOperationReport {
        _ = try configuration.validated()

        guard csvFile.rows.isEmpty == false else {
            throw JamfAppError.validation("Import a completed CSV with at least one serial number before running bulk import.")
        }

        return await runBulkOperation(kind: .upload, sourceName: csvFile.sourceName, items: csvFile.rows, serial: { $0.serialNumber }) { row in
            do {
                if let existingRecord = try await self.findRecord(serial: row.serialNumber) {
                    var draft = PreloadDraft(record: existingRecord, configuration: self.fieldConfiguration)
                    self.apply(row: row, to: &draft)
                    let record = try await self.updateRecord(id: existingRecord.id, from: draft, previous: existingRecord)
                    return (.success, "Updated record #\(record.id) from CSV line \(row.lineNumber).")
                } else {
                    var draft = PreloadDraft(configuration: self.fieldConfiguration)
                    self.apply(row: row, to: &draft)
                    let record = try await self.createRecord(from: draft)
                    return (.success, "Created record #\(record.id) from CSV line \(row.lineNumber).")
                }
            } catch {
                throw JamfAppError.validation("CSV line \(row.lineNumber): \(error.localizedDescription)")
            }
        }
    }

    /// Runs `perform` for each item, turning thrown errors into `.failed` report entries.
    private func runBulkOperation<Item>(
        kind: BulkOperationReport.Kind,
        sourceName: String?,
        items: [Item],
        serial: @MainActor (Item) -> String,
        perform: @MainActor (Item) async throws -> (BulkOperationReport.Outcome, String)
    ) async -> BulkOperationReport {
        var reportItems: [BulkOperationReport.Item] = []

        for item in items {
            let serialNumber = serial(item)
            do {
                let (outcome, message) = try await perform(item)
                reportItems.append(BulkOperationReport.Item(serialNumber: serialNumber, outcome: outcome, message: message))
            } catch {
                reportItems.append(BulkOperationReport.Item(serialNumber: serialNumber, outcome: .failed, message: error.localizedDescription))
            }
        }

        let report = BulkOperationReport(kind: kind, sourceName: sourceName, items: reportItems)
        recentActivity = report.summaryText
        return report
    }

    func exportUsedFieldsCSVTemplate(deviceType: PreloadDeviceType) async throws -> URL? {
        let data = Data(InventoryPreloadCSV.templateText(configuration: fieldConfiguration, deviceType: deviceType).utf8)
        let url = try CSVExporter.saveCSV(
            data: data,
            suggestedFilename: AppConstants.suggestedCSVTemplateFilename()
        )

        if let url {
            recentActivity = "Saved the used-fields CSV template to \(url.lastPathComponent)."
        } else {
            recentActivity = "CSV template export cancelled."
        }

        return url
    }

    func exportSerialsOnlyCSVTemplate() async throws -> URL? {
        let data = Data(InventoryPreloadCSV.serialsOnlyTemplateText().utf8)
        let url = try CSVExporter.saveCSV(
            data: data,
            suggestedFilename: AppConstants.suggestedSerialsOnlyCSVTemplateFilename()
        )

        if let url {
            recentActivity = "Saved the serials-only CSV template to \(url.lastPathComponent)."
        } else {
            recentActivity = "Serials-only CSV template export cancelled."
        }

        return url
    }

    func exportCSV() async throws -> URL? {
        let client = try makeClient()
        let data = try await client.exportCSV()
        let url = try CSVExporter.saveCSV(
            data: data,
            suggestedFilename: AppConstants.suggestedCSVFilename()
        )

        if let url {
            recentActivity = "Saved the CSV export to \(url.lastPathComponent)."
        } else {
            recentActivity = "CSV export cancelled."
        }

        return url
    }

    private func makeClient() throws -> JamfAPIClient {
        try JamfAPIClient(configuration: configuration.validated())
    }

    private func apply(_ snapshot: JamfConfigurationSnapshot) {
        configuration = snapshot.configuration
        savedServerURLs = snapshot.savedServerURLs

        if snapshot.configuration.isComplete {
            connectionState = .unknown
        } else {
            connectionState = .needsConfiguration
        }
    }

    private func apply(row: ImportedBulkCSVRow, to draft: inout PreloadDraft) {
        draft.serialNumber = row.serialNumber

        if let deviceType = row.deviceType {
            draft.deviceType = PreloadDeviceType(jamfValue: deviceType)
        }

        for field in fieldConfiguration.editableFields {
            if let value = row.values[field.id] {
                draft.values[field.id] = value
            }
        }
    }
}

enum ConnectionState: Equatable {
    case needsConfiguration
    case unknown
    case testing
    case connected(String)
    case failed(String)

    var title: String {
        switch self {
        case .needsConfiguration:
            "Configuration Needed"
        case .unknown:
            "Not Tested"
        case .testing:
            "Testing Connection"
        case .connected:
            "Connected"
        case .failed:
            "Attention Needed"
        }
    }

    var detail: String {
        switch self {
        case .needsConfiguration:
            "Save a Jamf URL and API credentials in Settings."
        case .unknown:
            "Run a connection test to confirm authentication and permissions."
        case .testing:
            "Contacting Jamf Pro..."
        case let .connected(message),
             let .failed(message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .needsConfiguration:
            "gearshape.2"
        case .unknown:
            "questionmark.circle"
        case .testing:
            "bolt.horizontal.circle"
        case .connected:
            "checkmark.seal"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}
