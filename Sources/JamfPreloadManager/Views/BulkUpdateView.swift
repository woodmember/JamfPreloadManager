import SwiftUI

struct BulkUpdateView: View {
    enum Workflow: String, CaseIterable, Identifiable {
        case templateFromSerials
        case filledCSV
        case delete

        var id: Self { self }

        var title: String {
            switch self {
            case .templateFromSerials:
                "Bulk Update - Serials Only CSV"
            case .filledCSV:
                "Bulk Update - Completed CSV"
            case .delete:
                "Bulk Delete"
            }
        }

        var description: String {
            switch self {
            case .templateFromSerials:
                "Import a CSV of serial numbers, apply the same configured field values to every row, then process each record through the standard create or update API."
            case .filledCSV:
                "Download a CSV template built from your configured fields, fill it in, then let the app create or update each row one at a time."
            case .delete:
                "Import a CSV of serial numbers and permanently delete every matching preload record."
            }
        }

        var actionTitle: String {
            switch self {
            case .templateFromSerials:
                "Process Prepared CSV"
            case .filledCSV:
                "Process Filled CSV"
            case .delete:
                "Delete Imported Entries"
            }
        }

        var systemImage: String {
            switch self {
            case .templateFromSerials:
                "tablecells.badge.ellipsis"
            case .filledCSV:
                "square.and.arrow.up"
            case .delete:
                "trash"
            }
        }
    }

    let model: AppModel

    @State private var workflow: Workflow = .templateFromSerials
    @State private var draft = PreloadDraft()
    @State private var templateDeviceType: PreloadDeviceType = .computer
    @State private var editorGeneration = 0
    @State private var didInitialize = false
    @State private var importedSerials: ImportedSerialList?
    @State private var importedCSV: ImportedBulkCSVFile?
    @State private var bulkReport: BulkOperationReport?
    @State private var feedback = "Choose a bulk workflow, then import the CSV you want to process."
    @State private var alertMessage: String?
    @State private var isWorking = false
    @State private var isExportingTemplate = false
    @State private var showBulkDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bulk Update")
                        .font(.largeTitle.weight(.semibold))
                    Text("Centralized CSV workflows for bulk create, overwrite, and delete actions.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Workflow") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Bulk Workflow", selection: $workflow) {
                            ForEach(Workflow.allCases) { workflow in
                                Text(workflow.title).tag(workflow)
                            }
                        }
                        .pickerStyle(.segmented)

                        Label(workflow.description, systemImage: workflow.systemImage)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                switch workflow {
                case .templateFromSerials:
                    serialTemplateWorkflow
                case .filledCSV:
                    filledCSVWorkflow
                case .delete:
                    deleteWorkflow
                }

                HStack {
                    if workflow == .delete {
                        Button(role: .destructive) {
                            showBulkDeleteConfirmation = true
                        } label: {
                            Label(isWorking ? "Deleting..." : deleteButtonTitle, systemImage: "trash")
                        }
                        .disabled(isActionDisabled)
                    } else {
                        Button {
                            runBulkAction()
                        } label: {
                            Label(isWorking ? "Working..." : uploadButtonTitle, systemImage: "square.and.arrow.up")
                        }
                        .disabled(isActionDisabled)
                    }

                    Text(feedback)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let bulkReport {
                    BulkOperationReportView(report: bulkReport)
                }
            }
            .padding(28)
        }
        .onAppear {
            guard didInitialize == false else { return }
            didInitialize = true
            resetDraft()
        }
        .onChange(of: workflow) { _, _ in
            bulkReport = nil
            feedback = workflow.description
        }
        .onChange(of: model.fieldConfiguration) { _, _ in
            resetDraft()
        }
        .confirmationDialog(
            "Delete the imported preload entries?",
            isPresented: $showBulkDeleteConfirmation,
            presenting: importedSerials
        ) { importedSerials in
            Button("Delete \(importedSerials.count) Entries", role: .destructive) {
                deleteImportedSerials(importedSerials)
            }
            Button("Cancel", role: .cancel) {}
        } message: { importedSerials in
            Text("This will look up and permanently delete every preload record found in \(importedSerials.sourceName).")
        }
        .errorAlert($alertMessage)
    }

    private var serialTemplateWorkflow: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Template Tools") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download the serials-only CSV template if you want a starter file with just the serial number column, then import that file below.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        exportSerialsOnlyTemplate()
                    } label: {
                        Label(isExportingTemplate ? "Saving Template..." : "Download Serials Only CSV Template", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking || isExportingTemplate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BulkSerialImportSection(
                importedSerials: importedSerials,
                isBusy: isWorking || isExportingTemplate,
                buttonTitle: "Import Serial CSV",
                instructions: "Import a CSV of serial numbers. The device type and values you set below are applied to every serial before each record is created or updated.",
                importAction: importSerialCSV,
                clearAction: clearImportedSerials
            )

            EntryDetailsSection(
                draft: $draft,
                configuration: model.fieldConfiguration,
                serialIsEditable: false,
                showsSerialField: false
            )
            .id(editorGeneration)
        }
    }

    private var filledCSVWorkflow: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Template Tools") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download the completed CSV template, fill in the fields you want the app to process, then import the finished file using the import box below.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Any matching serial is updated. Any new serial is created. Blank CSV cells are left unchanged for existing records.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Generate the template for:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Template device type", selection: $templateDeviceType) {
                        ForEach(PreloadDeviceType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320, alignment: .leading)

                    Text("The template includes a Device Type column, and its example first row is pre-filled with \"\(templateDeviceType.title)\" so you know what to enter for every row.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        exportCompletedTemplate()
                    } label: {
                        Label(isExportingTemplate ? "Saving Template..." : "Download \(templateDeviceType.title) CSV Template", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isWorking || isExportingTemplate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Import Completed CSV") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import a completed CSV file that matches the completed template.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        importFilledCSV()
                    } label: {
                        Label("Import Filled CSV", systemImage: "doc.text")
                    }
                    .disabled(isWorking || isExportingTemplate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Imported CSV") {
                    if let importedCSV {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Source File") {
                            Text(importedCSV.sourceName)
                        }

                        LabeledContent("Rows") {
                            Text("\(importedCSV.rowCount)")
                        }

                        LabeledContent("Columns") {
                            Text(importedCSV.headers.joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                        }

                        Text(importedCSV.previewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Clear Imported CSV", role: .destructive) {
                            clearImportedCSV()
                        }
                        .disabled(isWorking)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No CSV Imported",
                        systemImage: "tablecells.badge.ellipsis",
                        description: Text("Import a completed CSV that includes at least a serial number column.")
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var deleteWorkflow: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Admin Notice") {
                Text("Deleting preload records cannot be undone. Use this only when those records should no longer exist in Jamf.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            BulkSerialImportSection(
                importedSerials: importedSerials,
                isBusy: isWorking,
                buttonTitle: "Import Serial CSV",
                instructions: "Import a CSV of serial numbers to delete. Each serial will be looked up first, then any matching preload record will be permanently removed.",
                importAction: importSerialCSV,
                clearAction: clearImportedSerials
            )
        }
    }

    private func runBulkAction() {
        Task {
            isWorking = true

            do {
                let report: BulkOperationReport

                switch workflow {
                case .templateFromSerials:
                    guard let importedSerials else {
                        throw JamfAppError.validation("Import a CSV of serial numbers before uploading.")
                    }
                    report = try await model.bulkUploadRecords(from: draft, importedSerials: importedSerials)

                case .filledCSV:
                    guard let importedCSV else {
                        throw JamfAppError.validation("Import a completed CSV before uploading.")
                    }
                    report = try await model.bulkUploadRecords(csvFile: importedCSV)

                case .delete:
                    throw JamfAppError.validation("Use the delete button to confirm the bulk delete workflow.")
                }

                bulkReport = report
                feedback = report.summaryText
            } catch {
                alertMessage = error.localizedDescription
            }

            isWorking = false
        }
    }

    private func deleteImportedSerials(_ importedSerials: ImportedSerialList) {
        Task {
            isWorking = true

            do {
                let report = try await model.bulkDeleteRecords(importedSerials: importedSerials)
                bulkReport = report
                feedback = report.summaryText
            } catch {
                alertMessage = error.localizedDescription
            }

            isWorking = false
        }
    }

    private func exportSerialsOnlyTemplate() {
        Task {
            isExportingTemplate = true

            do {
                _ = try await model.exportSerialsOnlyCSVTemplate()
                feedback = "Saved the serials-only CSV template."
            } catch {
                alertMessage = error.localizedDescription
            }

            isExportingTemplate = false
        }
    }

    private func exportCompletedTemplate() {
        Task {
            isExportingTemplate = true

            do {
                _ = try await model.exportUsedFieldsCSVTemplate(deviceType: templateDeviceType)
                feedback = "Saved the \(templateDeviceType.title) CSV template."
            } catch {
                alertMessage = error.localizedDescription
            }

            isExportingTemplate = false
        }
    }

    private func importSerialCSV() {
        do {
            if let importedSerialList = try CSVSerialImporter.importSerials() {
                importedSerials = importedSerialList
                bulkReport = nil
                feedback = "Imported \(importedSerialList.count) serials from \(importedSerialList.sourceName)."
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func resetDraft() {
        draft = PreloadDraft(configuration: model.fieldConfiguration)
        editorGeneration += 1
    }

    private func importFilledCSV() {
        do {
            if let file = try InventoryPreloadCSV.importFilledCSV(configuration: model.fieldConfiguration) {
                importedCSV = file
                bulkReport = nil
                feedback = "Imported \(file.rowCount) rows from \(file.sourceName)."
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func clearImportedSerials() {
        importedSerials = nil
        bulkReport = nil
        feedback = workflow.description
    }

    private func clearImportedCSV() {
        importedCSV = nil
        bulkReport = nil
        feedback = workflow.description
    }

    private var uploadButtonTitle: String {
        switch workflow {
        case .templateFromSerials:
            if let importedSerials {
                return "Upload \(importedSerials.count) Prepared Rows"
            }
        case .filledCSV:
            if let importedCSV {
                return "Upload \(importedCSV.rowCount) Filled Rows"
            }
        case .delete:
            break
        }

        return workflow.actionTitle
    }

    private var deleteButtonTitle: String {
        guard let importedSerials else {
            return workflow.actionTitle
        }

        return "Delete \(importedSerials.count) Entries"
    }

    private var isActionDisabled: Bool {
        switch workflow {
        case .templateFromSerials:
            return isWorking || isExportingTemplate || importedSerials == nil || draft.hasValidRequiredFieldValues(configuration: model.fieldConfiguration) == false
        case .filledCSV:
            return isWorking || isExportingTemplate || importedCSV == nil
        case .delete:
            return isWorking || importedSerials == nil
        }
    }

}
