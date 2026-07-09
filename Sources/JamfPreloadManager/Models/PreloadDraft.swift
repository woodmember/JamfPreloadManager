import Foundation

/// Editable, in-progress values for a single preload record. Values are keyed by
/// `PreloadField.id`; the serial number is tracked separately because it is always
/// present and required regardless of the configuration.
struct PreloadDraft: Sendable, Equatable {
    var serialNumber = ""
    var values: [String: String] = [:]

    init() {}

    /// Creates a draft pre-populated with each configured field's default value.
    init(configuration: FieldConfiguration) {
        for field in configuration.fields {
            values[field.id] = field.defaultValue
        }
    }

    /// Creates a draft populated from an existing record for the given configuration.
    init(record: PreloadRecord, configuration: FieldConfiguration) {
        serialNumber = record.serialNumber
        for field in configuration.fields {
            values[field.id] = record.value(for: field) ?? field.defaultValue
        }
    }

    var normalizedSerialNumber: String {
        serialNumber.uppercased().removingAllWhitespace
    }

    func value(for field: PreloadField) -> String {
        (values[field.id] ?? "").trimmed
    }

    /// Whether every required configured field currently has a value. Does not
    /// consider the serial number (bulk-from-serials supplies it per row).
    func hasValidRequiredFieldValues(configuration: FieldConfiguration) -> Bool {
        configuration.fields.allSatisfy { field in
            field.isRequired == false || value(for: field).isEmpty == false
        }
    }

    /// Whether the serial number and every required field currently have a value.
    func hasValidRequiredValues(configuration: FieldConfiguration) -> Bool {
        normalizedSerialNumber.isEmpty == false && hasValidRequiredFieldValues(configuration: configuration)
    }

    func validatedSubmission(configuration: FieldConfiguration) throws -> PreloadSubmission {
        let serialNumber = normalizedSerialNumber
        guard serialNumber.isEmpty == false else {
            throw JamfAppError.validation("Serial number is required.")
        }

        var deviceType = AppConstants.deviceType
        var standardValues: [String: String] = [:]
        var extensionAttributes: [(name: String, value: String)] = []

        for field in configuration.fields {
            let value = value(for: field)

            if field.isRequired, value.isEmpty {
                throw JamfAppError.validation("\(field.displayName) is required.")
            }

            guard value.isEmpty == false else {
                continue
            }

            switch field.kind {
            case .standard:
                if field.isDeviceType {
                    deviceType = value
                } else {
                    standardValues[field.key] = value
                }
            case .extensionAttribute:
                extensionAttributes.append((name: field.key, value: value))
            }
        }

        return PreloadSubmission(
            serialNumber: serialNumber,
            deviceType: deviceType,
            standardValues: standardValues,
            extensionAttributes: extensionAttributes
        )
    }
}

struct PreloadSubmission: Sendable {
    let serialNumber: String
    let deviceType: String
    let standardValues: [String: String]
    let extensionAttributes: [(name: String, value: String)]
}
