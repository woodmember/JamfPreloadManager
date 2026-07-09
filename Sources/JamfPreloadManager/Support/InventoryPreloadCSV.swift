import Foundation

/// Builds and parses inventory-preload CSV files whose columns are driven by the
/// active `FieldConfiguration`. The Serial Number column is always present; every
/// other column comes from the configured fields (standard fields and extension
/// attributes alike), using each field's display name as the header.
enum InventoryPreloadCSV {
    static let serialHeader = StandardPreloadField.serialNumber.csvHeader

    private static var serialAliases: Set<String> {
        var aliases = StandardPreloadField.serialNumber.aliases
        aliases.insert(CSVSupport.normalizedHeader(serialHeader))
        return aliases
    }

    static func columnHeaders(for configuration: FieldConfiguration) -> [String] {
        [serialHeader] + configuration.fields.map(\.displayName)
    }

    static func templateText(configuration: FieldConfiguration) -> String {
        CSVSupport.csvLine(columnHeaders(for: configuration)) + "\n"
    }

    static func serialsOnlyTemplateText() -> String {
        CSVSupport.csvLine([serialHeader]) + "\n"
    }

    @MainActor
    static func importFilledCSV(configuration: FieldConfiguration) throws -> ImportedBulkCSVFile? {
        guard let url = CSVSupport.chooseCSVFile() else {
            return nil
        }

        return try parseFilledCSV(from: url, configuration: configuration)
    }

    static func parseFilledCSV(from url: URL, configuration: FieldConfiguration) throws -> ImportedBulkCSVFile {
        let text = try CSVSupport.readText(from: url)
        let rows = sanitizedRows(from: text)
        guard let headerRow = rows.first else {
            throw JamfAppError.validation("The selected CSV did not include a header row.")
        }

        let headerMap = makeHeaderMap(from: headerRow)

        guard let serialIndex = index(matching: serialAliases, in: headerMap) else {
            throw JamfAppError.validation("The selected CSV is missing a Serial Number column.")
        }

        // Resolve which column feeds each configured field.
        var fieldColumnIndex: [String: Int] = [:]
        for field in configuration.fields {
            if let columnIndex = index(matching: field.csvHeaderAliases, in: headerMap) {
                fieldColumnIndex[field.id] = columnIndex
            }
        }

        let deviceTypeIndex = index(matching: StandardPreloadField.deviceType.aliases, in: headerMap)
        let dataRows = Array(rows.dropFirst())

        let importedRows = dataRows.enumerated().compactMap { offset, row -> ImportedBulkCSVRow? in
            guard let serialNumber = normalizedSerial(at: serialIndex, in: row) else {
                return nil
            }

            var values: [String: String] = [:]
            for field in configuration.fields {
                guard let columnIndex = fieldColumnIndex[field.id],
                      let value = rawValue(at: columnIndex, in: row) else {
                    continue
                }
                values[field.id] = value
            }

            let deviceType = deviceTypeIndex.flatMap { rawValue(at: $0, in: row) }

            return ImportedBulkCSVRow(
                lineNumber: offset + 2,
                serialNumber: serialNumber,
                deviceType: deviceType,
                values: values
            )
        }

        guard importedRows.isEmpty == false else {
            throw JamfAppError.validation("The selected CSV did not contain any serial numbers.")
        }

        let matchedHeaders = [serialHeader] + configuration.fields
            .filter { fieldColumnIndex[$0.id] != nil }
            .map(\.displayName)

        return ImportedBulkCSVFile(
            sourceName: url.lastPathComponent,
            csvText: makePreviewCSV(rows: importedRows, configuration: configuration),
            serialNumbers: CSVSupport.uniqueValues(from: importedRows.map(\.serialNumber)),
            headers: matchedHeaders,
            rowCount: importedRows.count,
            rows: importedRows
        )
    }

    private static func makePreviewCSV(rows: [ImportedBulkCSVRow], configuration: FieldConfiguration) -> String {
        let headers = columnHeaders(for: configuration)
        let lines = [CSVSupport.csvLine(headers)] + rows.map { row in
            var line = [row.serialNumber]
            line.append(contentsOf: configuration.fields.map { row.values[$0.id] ?? "" })
            return CSVSupport.csvLine(line)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func sanitizedRows(from text: String) -> [[String]] {
        CSVSupport.parseRows(text)
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
    }

    private static func normalizedSerial(at index: Int, in row: [String]) -> String? {
        guard row.indices.contains(index) else {
            return nil
        }

        return row[index]
            .trimmed
            .uppercased()
            .removingAllWhitespace
            .nilIfBlank
    }

    private static func rawValue(at index: Int, in row: [String]) -> String? {
        guard row.indices.contains(index) else {
            return nil
        }

        return row[index].trimmed.nilIfBlank
    }

    private static func makeHeaderMap(from headers: [String]) -> [String: Int] {
        var headerMap: [String: Int] = [:]

        for (offset, value) in headers.enumerated() {
            let normalized = CSVSupport.normalizedHeader(value)
            guard normalized.isEmpty == false, headerMap[normalized] == nil else {
                continue
            }
            headerMap[normalized] = offset
        }

        return headerMap
    }

    private static func index(matching aliases: Set<String>, in headerMap: [String: Int]) -> Int? {
        for alias in aliases {
            if let index = headerMap[alias] {
                return index
            }
        }
        return nil
    }
}
