import Foundation

struct ImportedSerialList: Equatable, Sendable {
    let sourceName: String
    let serialNumbers: [String]

    var count: Int {
        serialNumbers.count
    }

    var previewText: String {
        let previewItems = Array(serialNumbers.prefix(8))
        var lines = previewItems

        if serialNumbers.count > previewItems.count {
            lines.append("...and \(serialNumbers.count - previewItems.count) more")
        }

        return lines.joined(separator: "\n")
    }
}
