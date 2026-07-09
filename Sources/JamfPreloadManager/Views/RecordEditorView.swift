import SwiftUI

struct RecordEditorView: View {
    enum Mode {
        case add
        case modify

        var title: String {
            switch self {
            case .add:
                "Add Entry"
            case .modify:
                "Modify Entry"
            }
        }

        var description: String {
            switch self {
            case .add:
                "Create a new inventory preload record using the fields configured for this app."
            case .modify:
                "Load an existing record by serial number, review its current values, then update the preload fields."
            }
        }

        var actionTitle: String {
            switch self {
            case .add:
                "Create Entry"
            case .modify:
                "Save Changes"
            }
        }
    }

    let model: AppModel
    let mode: Mode

    @State private var draft = PreloadDraft()
    @State private var loadedRecord: PreloadRecord?
    @State private var editorGeneration = 0
    @State private var feedback: String
    @State private var alertMessage: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var didInitialize = false

    init(model: AppModel, mode: Mode) {
        self.model = model
        self.mode = mode
        _feedback = State(initialValue: mode.description)
    }

    private var configuration: FieldConfiguration {
        model.fieldConfiguration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(mode.title)
                        .font(.largeTitle.weight(.semibold))
                    Text(mode.description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Workflow") {
                    Text(workflowDescription)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if mode == .modify {
                    GroupBox("Load Existing Record") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Enter serial number", text: $draft.serialNumber)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .disabled(isSaving || loadedRecord != nil)
                                .onSubmit(loadRecord)

                            HStack {
                                Button {
                                    loadRecord()
                                } label: {
                                    Label(isLoading ? "Loading..." : "Load Record", systemImage: "arrow.clockwise")
                                }
                                .disabled(isLoading || isSaving || loadedRecord != nil)

                                if loadedRecord != nil {
                                    Button("Load Another Serial") {
                                        loadedRecord = nil
                                        resetDraft()
                                    }
                                    .disabled(isLoading || isSaving)
                                }

                                Text(feedback)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    GroupBox("Create New Record") {
                        Text("Fill in the serial number and the configured preload fields below, then create the record in Jamf Pro.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let loadedRecord {
                    RecordSummaryView(title: "Current Values", record: loadedRecord, configuration: configuration)
                }

                EntryDetailsSection(
                    draft: $draft,
                    configuration: configuration,
                    serialIsEditable: mode == .add || loadedRecord == nil,
                    showsSerialField: true
                )
                .id(editorGeneration)

                HStack {
                    Button {
                        saveRecord()
                    } label: {
                        Label(isSaving ? "Working..." : actionButtonTitle, systemImage: mode == .add ? "plus.circle.fill" : "square.and.arrow.down")
                    }
                    .disabled(isActionDisabled)

                    Text(feedback)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
        .onAppear {
            guard didInitialize == false else { return }
            didInitialize = true
            resetDraft()
        }
        .onChange(of: configuration) { _, _ in
            loadedRecord = nil
            resetDraft()
        }
        .errorAlert($alertMessage)
    }

    private func resetDraft() {
        draft = PreloadDraft(configuration: configuration)
        editorGeneration += 1
    }

    private func loadRecord() {
        Task {
            isLoading = true

            do {
                let record = try await model.findRecord(serial: draft.serialNumber)
                guard let record else {
                    loadedRecord = nil
                    feedback = "No preload record exists for \(draft.normalizedSerialNumber)."
                    isLoading = false
                    return
                }

                loadedRecord = record
                draft = PreloadDraft(record: record, configuration: configuration)
                editorGeneration += 1
                feedback = "Loaded record #\(record.id) for \(record.serialNumber)."
            } catch {
                alertMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func saveRecord() {
        Task {
            isSaving = true

            do {
                switch mode {
                case .add:
                    let record = try await model.createRecord(from: draft)
                    loadedRecord = record
                    draft = PreloadDraft(record: record, configuration: configuration)
                    editorGeneration += 1
                    feedback = "Created preload record #\(record.id) for \(record.serialNumber)."

                case .modify:
                    guard let loadedRecord else {
                        throw JamfAppError.validation("Load a record before saving changes.")
                    }

                    let record = try await model.updateRecord(id: loadedRecord.id, from: draft, previous: loadedRecord)
                    self.loadedRecord = record
                    draft = PreloadDraft(record: record, configuration: configuration)
                    editorGeneration += 1
                    feedback = "Updated preload record #\(record.id) for \(record.serialNumber)."
                }
            } catch {
                alertMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private var workflowDescription: String {
        switch mode {
        case .add:
            "Create one new preload record by entering a single serial number and its preload details."
        case .modify:
            "Load one existing record, review its current values, and save changes back to Jamf."
        }
    }

    private var actionButtonTitle: String {
        mode.actionTitle
    }

    private var isActionDisabled: Bool {
        let missingRequired = mode == .add && draft.hasValidRequiredValues(configuration: configuration) == false
        return isSaving || isLoading || missingRequired || (mode == .modify && loadedRecord == nil)
    }

}

struct EntryDetailsSection: View {
    @Binding var draft: PreloadDraft
    let configuration: FieldConfiguration
    let serialIsEditable: Bool
    let showsSerialField: Bool

    var body: some View {
        GroupBox("Preload Details") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                if showsSerialField {
                    GridRow {
                        fieldLabel("Serial Number", required: true)
                        TextField("Serial number", text: $draft.serialNumber)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disabled(serialIsEditable == false)
                    }
                }

                GridRow {
                    fieldLabel("Device Type", required: true)
                    Picker("", selection: $draft.deviceType) {
                        ForEach(PreloadDeviceType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                ForEach(configuration.editableFields) { field in
                    GridRow {
                        fieldLabel(field.displayName, required: field.isRequired)
                        FieldEditorRow(field: field, value: binding(for: field))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func binding(for field: PreloadField) -> Binding<String> {
        Binding(
            get: { draft.values[field.id] ?? "" },
            set: { draft.values[field.id] = $0 }
        )
    }

    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.headline)
            if required {
                Text("*")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 160, alignment: .leading)
    }
}

/// Renders the appropriate input for one configured field: a free-text field, or a
/// list picker with an optional custom-value entry.
struct FieldEditorRow: View {
    let field: PreloadField
    @Binding var value: String

    @State private var selection = AppConstants.selectPlaceholderChoice

    var body: some View {
        switch field.inputType {
        case .freeText:
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list:
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $selection) {
                    Text("Select \(field.displayName)").tag(AppConstants.selectPlaceholderChoice)
                    ForEach(field.listOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                    if field.allowsCustomEntry {
                        Divider()
                        Text("Custom…").tag(AppConstants.customChoice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if selection == AppConstants.customChoice {
                    TextField("Enter custom \(field.displayName)", text: $value)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .onAppear(perform: syncSelectionFromValue)
            .onChange(of: selection) { _, newSelection in
                switch newSelection {
                case AppConstants.selectPlaceholderChoice:
                    value = ""
                case AppConstants.customChoice:
                    break // value is driven by the custom text field
                default:
                    value = newSelection
                }
            }
        }
    }

    private var placeholder: String {
        field.isRequired ? "\(field.displayName) (required)" : "Optional \(field.displayName)"
    }

    private func syncSelectionFromValue() {
        if value.isEmpty {
            selection = AppConstants.selectPlaceholderChoice
        } else if field.listOptions.contains(value) {
            selection = value
        } else if field.allowsCustomEntry {
            selection = AppConstants.customChoice
        } else {
            selection = AppConstants.selectPlaceholderChoice
        }
    }
}
