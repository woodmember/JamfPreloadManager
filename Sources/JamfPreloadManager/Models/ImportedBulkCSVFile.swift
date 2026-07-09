import Foundation

struct ImportedBulkCSVRow: Equatable, Sendable {
    let lineNumber: Int
    let serialNumber: String
    let deviceType: String?
    /// Parsed values keyed by `PreloadField.id`.
    let values: [String: String]
}

struct ImportedBulkCSVFile: Equatable, Sendable {
    let sourceName: String
    let csvText: String
    let serialNumbers: [String]
    let headers: [String]
    let rowCount: Int
    let rows: [ImportedBulkCSVRow]

    var previewText: String {
        let allLines = csvText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let previewItems = Array(allLines.prefix(7))
        var lines = previewItems

        if allLines.count > previewItems.count {
            lines.append("...and \(allLines.count - previewItems.count) more lines")
        }

        return lines.joined(separator: "\n")
    }
}
