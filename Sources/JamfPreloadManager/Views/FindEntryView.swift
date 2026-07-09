import SwiftUI

struct FindEntryView: View {
    let model: AppModel

    @State private var serialNumber = ""
    @State private var foundRecord: PreloadRecord?
    @State private var feedback = "Search by serial number to inspect the current inventory preload record."
    @State private var alertMessage: String?
    @State private var isSearching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find Entry")
                        .font(.largeTitle.weight(.semibold))
                    Text("Look up a device serial number and review the exact preload values currently stored in Jamf.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Serial Lookup") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Enter serial number", text: $serialNumber)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(search)

                        HStack {
                            Button {
                                search()
                            } label: {
                                Label(isSearching ? "Searching..." : "Find Entry", systemImage: "magnifyingglass")
                            }
                            .disabled(isSearching)

                            Text(feedback)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let foundRecord {
                    RecordSummaryView(title: "Lookup Result", record: foundRecord, configuration: model.fieldConfiguration)
                } else {
                    ContentUnavailableView(
                        "No Record Loaded",
                        systemImage: "shippingbox",
                        description: Text("Run a lookup to see the current preload details for a Mac.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .padding(28)
        }
        .errorAlert($alertMessage)
    }

    private func search() {
        Task {
            isSearching = true
            foundRecord = nil

            do {
                let result = try await model.findRecord(serial: serialNumber)
                if let result {
                    foundRecord = result
                    feedback = "Found preload record #\(result.id) for \(result.serialNumber)."
                } else {
                    feedback = "No preload record exists for \(serialNumber.uppercased().removingAllWhitespace)."
                }
            } catch {
                alertMessage = error.localizedDescription
            }

            isSearching = false
        }
    }

}
