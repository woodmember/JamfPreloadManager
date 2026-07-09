import AppKit
import Foundation
import UniformTypeIdentifiers

enum CSVExporter {
    @MainActor
    static func saveCSV(data: Data, suggestedFilename: String) throws -> URL? {
        try saveFile(data: data, suggestedFilename: suggestedFilename, contentTypes: [.commaSeparatedText])
    }

    @MainActor
    static func saveFile(data: Data, suggestedFilename: String, contentTypes: [UTType]) throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        if contentTypes.isEmpty == false {
            panel.allowedContentTypes = contentTypes
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}
