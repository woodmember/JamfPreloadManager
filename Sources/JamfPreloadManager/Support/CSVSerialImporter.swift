import AppKit
import Foundation

enum CSVSerialImporter {
    @MainActor
    static func importSerials() throws -> ImportedSerialList? {
        guard let url = CSVSupport.chooseCSVFile() else {
            return nil
        }

        return try parseSerials(from: url)
    }

    static func parseSerials(from url: URL) throws -> ImportedSerialList {
        let text = try CSVSupport.readText(from: url)
        let rows = CSVSupport.parseRows(text)
        let serialNumbers = extractSerialNumbers(from: rows)

        guard serialNumbers.isEmpty == false else {
            throw JamfAppError.validation("The selected CSV did not contain any serial numbers.")
        }

        return ImportedSerialList(
            sourceName: url.lastPathComponent,
            serialNumbers: serialNumbers
        )
    }

    private static func extractSerialNumbers(from rows: [[String]]) -> [String] {
        let sanitizedRows = rows
            .map { row in
                row.map { value in
                    value
                        .replacingOccurrences(of: "\u{feff}", with: "")
                        .trimmed
                }
            }
            .filter { row in
                row.contains { $0.isEmpty == false }
            }

        guard let firstRow = sanitizedRows.first else {
            return []
        }

        let serialColumnIndex = firstRow.firstIndex(where: isSerialHeader)
        let dataRows = serialColumnIndex == nil ? sanitizedRows : Array(sanitizedRows.dropFirst())

        let extracted = dataRows.compactMap { row -> String? in
            let rawValue: String?

            if let serialColumnIndex {
                rawValue = row.indices.contains(serialColumnIndex) ? row[serialColumnIndex] : nil
            } else {
                rawValue = row.first(where: { $0.isEmpty == false })
            }

            return normalizeSerial(rawValue)
        }

        let serials = serialColumnIndex == nil ? dropHeaderLikeFirstValue(from: extracted) : extracted
        return CSVSupport.uniqueValues(from: serials)
    }

    private static func isSerialHeader(_ value: String) -> Bool {
        let normalized = CSVSupport.normalizedHeader(value)

        return normalized == "serial" || normalized == "serialnumber" || normalized == "serialno"
    }

    private static func normalizeSerial(_ value: String?) -> String? {
        value?
            .trimmed
            .uppercased()
            .removingAllWhitespace
            .nilIfBlank
    }

    private static func dropHeaderLikeFirstValue(from values: [String]) -> [String] {
        guard let first = values.first, isSerialHeader(first) else {
            return values
        }

        return Array(values.dropFirst())
    }
}
