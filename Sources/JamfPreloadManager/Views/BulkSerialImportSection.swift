import SwiftUI

struct BulkSerialImportSection: View {
    let importedSerials: ImportedSerialList?
    let isBusy: Bool
    let buttonTitle: String
    let instructions: String
    let importAction: () -> Void
    let clearAction: () -> Void

    var body: some View {
        GroupBox("Bulk CSV Import") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: importAction) {
                        Label(buttonTitle, systemImage: "tray.and.arrow.down")
                    }
                    .disabled(isBusy)

                    if importedSerials != nil {
                        Button("Clear List", role: .cancel, action: clearAction)
                            .disabled(isBusy)
                    }
                }

                Text(instructions)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let importedSerials {
                    LabeledContent("Source") {
                        Text(importedSerials.sourceName)
                    }

                    LabeledContent("Serial Count") {
                        Text("\(importedSerials.count)")
                    }

                    ScrollView {
                        Text(importedSerials.previewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                } else {
                    Text("Import a CSV with one serial per row, or a column named Serial / Serial Number.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
