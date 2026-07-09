import SwiftUI

struct RecordSummaryView: View {
    let title: String
    let record: PreloadRecord
    let configuration: FieldConfiguration

    init(title: String = "Preload Record", record: PreloadRecord, configuration: FieldConfiguration) {
        self.title = title
        self.record = record
        self.configuration = configuration
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                summaryRow("Record ID", "\(record.id)")
                summaryRow("Serial Number", record.serialNumber)
                summaryRow("Device Type", record.deviceType)

                ForEach(configuration.editableFields) { field in
                    summaryRow(field.displayName, record.value(for: field) ?? "Not set")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
