import Foundation

struct BulkOperationReport: Equatable, Sendable {
    enum Kind: String, Sendable {
        case upload
        case delete

        var title: String {
            switch self {
            case .upload:
                "Bulk Import"
            case .delete:
                "Bulk Delete"
            }
        }

        var pastTenseVerb: String {
            switch self {
            case .upload:
                "processed"
            case .delete:
                "deleted"
            }
        }
    }

    enum Outcome: String, Sendable {
        case success
        case skipped
        case failed

        var title: String {
            rawValue.uppercased()
        }

        var systemImage: String {
            switch self {
            case .success:
                "checkmark.circle.fill"
            case .skipped:
                "arrow.uturn.forward.circle"
            case .failed:
                "xmark.circle.fill"
            }
        }
    }

    struct Item: Identifiable, Equatable, Sendable {
        let serialNumber: String
        let outcome: Outcome
        let message: String

        var id: String {
            "\(serialNumber)-\(outcome.rawValue)-\(message)"
        }
    }

    let kind: Kind
    let sourceName: String?
    let items: [Item]

    var processedCount: Int {
        items.count
    }

    var successCount: Int {
        items.filter { $0.outcome == .success }.count
    }

    var skippedCount: Int {
        items.filter { $0.outcome == .skipped }.count
    }

    var failedCount: Int {
        items.filter { $0.outcome == .failed }.count
    }

    var summaryText: String {
        "\(kind.title) finished. \(successCount) \(kind.pastTenseVerb), \(skippedCount) skipped, \(failedCount) failed."
    }

    var detailText: String {
        items.map { item in
            "[\(item.outcome.title)] \(item.serialNumber): \(item.message)"
        }
        .joined(separator: "\n")
    }
}
