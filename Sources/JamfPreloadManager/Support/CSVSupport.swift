import AppKit
import Foundation
import UniformTypeIdentifiers

enum CSVSupport {
    @MainActor
    static func chooseCSVFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    static func readText(from url: URL) throws -> String {
        let encodings: [String.Encoding] = [.utf8, .utf16, .unicode, .ascii, .macOSRoman]

        for encoding in encodings {
            if let value = try? String(contentsOf: url, encoding: encoding) {
                return value
            }
        }

        throw JamfAppError.validation("The selected file could not be read as text.")
    }

    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false

        func finishField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func finishRow() {
            if currentRow.isEmpty == false || currentField.isEmpty == false {
                finishField()
                rows.append(currentRow)
            }
            currentRow = []
        }

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if character == "\"" {
                let nextIndex = text.index(after: index)

                if isInsideQuotes, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    currentField.append("\"")
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == "," && isInsideQuotes == false {
                finishField()
            } else if character.isNewline && isInsideQuotes == false {
                finishRow()
            } else {
                currentField.append(character)
            }

            index = text.index(after: index)
        }

        if currentRow.isEmpty == false || currentField.isEmpty == false {
            finishRow()
        }

        return rows
    }

    static func normalizedHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{feff}", with: "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmed
    }

    static func csvLine(_ values: [String]) -> String {
        values.map(escapedCSVField).joined(separator: ",")
    }

    /// Removes duplicates while preserving first-seen order.
    static func uniqueValues(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func escapedCSVField(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
