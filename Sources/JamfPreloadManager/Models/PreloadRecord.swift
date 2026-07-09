import Foundation

struct PreloadRecord: Identifiable, Equatable, Sendable {
    let id: Int
    let serialNumber: String
    let deviceType: String
    /// Standard field values keyed by API key (e.g. "fullName").
    let standardValues: [String: String]
    /// Extension attribute values keyed by attribute name.
    let extensionAttributes: [String: String]

    init(
        id: Int,
        serialNumber: String,
        deviceType: String,
        standardValues: [String: String] = [:],
        extensionAttributes: [String: String] = [:]
    ) {
        self.id = id
        self.serialNumber = serialNumber
        self.deviceType = deviceType
        self.standardValues = standardValues
        self.extensionAttributes = extensionAttributes
    }

    /// The stored value for a configured field, if any.
    func value(for field: PreloadField) -> String? {
        switch field.kind {
        case .standard:
            switch field.standardField {
            case .serialNumber:
                return serialNumber.nilIfBlank
            case .deviceType:
                return deviceType.nilIfBlank
            default:
                return standardValues[field.key]?.nilIfBlank
            }
        case .extensionAttribute:
            return extensionAttributes[field.key]?.nilIfBlank
        }
    }
}
