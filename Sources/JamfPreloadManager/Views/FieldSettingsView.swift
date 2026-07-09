import SwiftUI
import UniformTypeIdentifiers

struct FieldSettingsView: View {
    let model: AppModel

    @State private var config = FieldConfiguration.neutralDefault
    @State private var newExtensionAttributeName = ""
    @State private var exportServerURL = ""
    @State private var exportClientID = ""
    @State private var feedback = "Choose which fields this app uses for adds, modifies, deletes, and bulk actions."
    @State private var alertMessage: String?
    @State private var didInitialize = false

    private var isManaged: Bool {
        model.isFieldConfigurationManaged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fields")
                .font(.largeTitle.weight(.semibold))

            Text("These fields drive the Add, Modify, Find and Bulk screens as well as the CSV templates the app generates and reads. Serial Number and Device Type (Computer / Mobile Device) are always included.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isManaged {
                managedBanner
            }

            Form {
                standardFieldsSection
                extensionAttributesSection
            }
            .formStyle(.grouped)
            .disabled(isManaged)

            exportDefaultsBox

            actionsBar
        }
        .onAppear {
            guard didInitialize == false else { return }
            didInitialize = true
            config = model.fieldConfiguration
            exportServerURL = model.configuration.serverURL
            exportClientID = model.configuration.clientID.nilIfBlank ?? model.managedDefaultClientID ?? ""
        }
        .onChange(of: model.fieldConfiguration) { _, newValue in
            config = newValue
        }
        .errorAlert($alertMessage)
    }

    private var managedBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Managed by your organization")
                    .font(.headline)
                Text("A configuration profile is supplying these settings, so they are read-only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var standardFieldsSection: some View {
        Section("Standard Jamf Fields") {
            ForEach(StandardPreloadField.configurable, id: \.self) { field in
                let id = PreloadField.standardID(field)
                let isEnabled = config.fields.contains { $0.id == id }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(field.csvHeader, isOn: standardEnabledBinding(field))
                        .toggleStyle(.switch)

                    if isEnabled {
                        FieldConfigEditor(field: fieldBinding(id: id))
                            .padding(.leading, 6)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var extensionAttributesSection: some View {
        Section("Extension Attributes") {
            let extensionAttributes = config.fields.filter { $0.kind == .extensionAttribute }

            if extensionAttributes.isEmpty {
                Text("No extension attributes configured yet. Add one below using the exact attribute name from Jamf Pro.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(extensionAttributes) { field in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(field.displayName)
                            .font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            config.fields.removeAll { $0.id == field.id }
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                    }

                    FieldConfigEditor(field: fieldBinding(id: field.id))
                        .padding(.leading, 6)
                }
                .padding(.vertical, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("New extension attribute name", text: $newExtensionAttributeName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addExtensionAttribute()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(newExtensionAttributeName.trimmed.isEmpty)
            }
        }
    }

    private var exportDefaultsBox: some View {
        GroupBox("Configuration Profile Defaults (optional)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Included only in the exported configuration profile as starting points for your org. Unlike the fields above, these are pre-populated but NOT locked — users can still change them. The Client Secret is never included (it stays in the Keychain).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Default Jamf Server URL (e.g. https://yourorg.jamfcloud.com)", text: $exportServerURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Default API Client ID (optional)", text: $exportClientID)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsBar: some View {
        HStack(spacing: 12) {
            if isManaged == false {
                Button {
                    save()
                } label: {
                    Label("Save Fields", systemImage: "square.and.arrow.down")
                }

                Button("Revert") {
                    config = model.fieldConfiguration
                    feedback = "Reverted to the saved field configuration."
                }
            }

            Button {
                exportConfigurationProfile()
            } label: {
                Label("Export Configuration Profile…", systemImage: "gearshape.arrow.triangle.2.circlepath")
            }

            Spacer()

            Text(feedback)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func addExtensionAttribute() {
        let name = newExtensionAttributeName.trimmed
        guard name.isEmpty == false else { return }

        let id = PreloadField.extensionAttributeID(name)
        guard config.fields.contains(where: { $0.id == id }) == false else {
            alertMessage = "An extension attribute named \"\(name)\" is already configured."
            return
        }

        config.fields.append(.extensionAttribute(name: name))
        newExtensionAttributeName = ""
        feedback = "Added extension attribute \"\(name)\". Remember to Save."
    }

    private func save() {
        var cleaned = config
        cleaned.fields = cleaned.fields.map { field in
            var field = field
            field.listOptions = field.listOptions
                .map(\.trimmed)
                .filter { $0.isEmpty == false }
            return field
        }

        do {
            try model.saveFieldConfiguration(cleaned)
            config = model.fieldConfiguration
            feedback = "Saved field configuration."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportConfigurationProfile() {
        do {
            let data = try ConfigurationProfileBuilder.makeProfileData(
                configuration: config,
                defaultServerURL: exportServerURL.nilIfBlank,
                defaultClientID: exportClientID.nilIfBlank
            )
            let mobileconfigType = UTType(filenameExtension: "mobileconfig") ?? .data
            if let url = try CSVExporter.saveFile(
                data: data,
                suggestedFilename: AppConstants.suggestedConfigurationProfileFilename(),
                contentTypes: [mobileconfigType]
            ) {
                feedback = "Exported configuration profile to \(url.lastPathComponent)."
            } else {
                feedback = "Configuration profile export cancelled."
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: - Bindings

    private func standardEnabledBinding(_ field: StandardPreloadField) -> Binding<Bool> {
        let id = PreloadField.standardID(field)
        return Binding(
            get: { config.fields.contains { $0.id == id } },
            set: { isOn in
                if isOn {
                    if config.fields.contains(where: { $0.id == id }) == false {
                        config.fields.append(.standard(field))
                    }
                } else {
                    config.fields.removeAll { $0.id == id }
                }
            }
        )
    }

    private func fieldBinding(id: String) -> Binding<PreloadField> {
        Binding(
            get: {
                config.fields.first(where: { $0.id == id })
                    ?? PreloadField(id: id, kind: .standard, key: "", displayName: "")
            },
            set: { newValue in
                if let index = config.fields.firstIndex(where: { $0.id == id }) {
                    config.fields[index] = newValue
                }
            }
        )
    }

}

/// Editor for a single field's input configuration (input type, list options,
/// custom entry, required). Shared by standard fields and extension attributes.
struct FieldConfigEditor: View {
    @Binding var field: PreloadField

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Input", selection: $field.inputType) {
                ForEach(FieldInputType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            if field.inputType == .list {
                Text("List Options (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: optionsBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                Toggle("Allow a custom typed value", isOn: $field.allowsCustomEntry)
                    .toggleStyle(.checkbox)
            }

            Toggle("Required", isOn: $field.isRequired)
                .toggleStyle(.checkbox)
        }
    }

    private var optionsBinding: Binding<String> {
        Binding(
            get: { field.listOptions.joined(separator: "\n") },
            set: { field.listOptions = $0.components(separatedBy: "\n") }
        )
    }
}
