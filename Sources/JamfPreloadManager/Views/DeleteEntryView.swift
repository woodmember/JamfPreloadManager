import SwiftUI

struct DeleteEntryView: View {
    let model: AppModel

    @State private var serialNumber = ""
    @State private var recordToDelete: PreloadRecord?
    @State private var feedback = "This screen is intended for Jamf admins when a preload record must be permanently removed."
    @State private var alertMessage: String?
    @State private var isSearching = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete Entry")
                        .font(.largeTitle.weight(.semibold))
                    Text("Admin-only permanent removal for preload records that should no longer exist in Jamf.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Workflow") {
                    Text("Find one record by serial number, inspect it, then confirm the deletion.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Admin Notice") {
                    Text("Deleting a preload record cannot be undone. Standard support workflows should prefer Find Entry or Modify Entry whenever possible.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Find Record to Delete") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Enter serial number", text: $serialNumber)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(findRecord)

                        HStack {
                            Button {
                                findRecord()
                            } label: {
                                Label(isSearching ? "Searching..." : "Find Record", systemImage: "magnifyingglass")
                            }
                            .disabled(isSearching || isDeleting)

                            Text(feedback)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let recordToDelete {
                    RecordSummaryView(title: "Pending Deletion", record: recordToDelete, configuration: model.fieldConfiguration)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(isDeleting ? "Deleting..." : "Delete Entry", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                } else {
                    ContentUnavailableView(
                        "No Record Selected",
                        systemImage: "trash.slash",
                        description: Text("Load a serial first so you can confirm exactly what will be removed.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .padding(28)
        }
        .confirmationDialog(
            "Delete this preload entry?",
            isPresented: $showDeleteConfirmation,
            presenting: recordToDelete
        ) { record in
            Button("Delete \(record.serialNumber)", role: .destructive) {
                delete(record)
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("This permanently deletes record #\(record.id) for serial \(record.serialNumber).")
        }
        .errorAlert($alertMessage)
    }

    private func findRecord() {
        Task {
            isSearching = true

            do {
                let result = try await model.findRecord(serial: serialNumber)
                if let result {
                    recordToDelete = result
                    feedback = "Loaded preload record #\(result.id). Review the details carefully before deleting."
                } else {
                    recordToDelete = nil
                    feedback = "No preload record exists for \(serialNumber.uppercased().removingAllWhitespace)."
                }
            } catch {
                alertMessage = error.localizedDescription
            }

            isSearching = false
        }
    }

    private func delete(_ record: PreloadRecord) {
        Task {
            isDeleting = true

            do {
                try await model.deleteRecord(record)
                feedback = "Deleted preload record #\(record.id) for \(record.serialNumber)."
                recordToDelete = nil
            } catch {
                alertMessage = error.localizedDescription
            }

            isDeleting = false
        }
    }

}
