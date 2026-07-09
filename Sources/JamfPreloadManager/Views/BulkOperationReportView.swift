import SwiftUI

struct BulkOperationReportView: View {
    let report: BulkOperationReport

    var body: some View {
        GroupBox(report.kind.title + " Results") {
            VStack(alignment: .leading, spacing: 12) {
                if let sourceName = report.sourceName {
                    LabeledContent("Source CSV") {
                        Text(sourceName)
                    }
                }

                LabeledContent("Processed") {
                    Text("\(report.processedCount)")
                }

                LabeledContent("Succeeded") {
                    Text("\(report.successCount)")
                }

                LabeledContent("Skipped") {
                    Text("\(report.skippedCount)")
                }

                LabeledContent("Failed") {
                    Text("\(report.failedCount)")
                }

                Text(report.summaryText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    Text(report.detailText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 240)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
