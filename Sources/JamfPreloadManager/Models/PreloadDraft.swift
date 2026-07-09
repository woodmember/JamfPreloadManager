import Foundation

/// Editable, in-progress values for a single preload record. Values are keyed by
/// `PreloadField.id`; the serial number and device type are tracked separately
/// because they are always present regardless of the configuration.
struct PreloadDraft: Sendable, Equatable {
    var serialNumber = ""
    var deviceType: PreloadDeviceType = .computer
    var values: [String: String] = [:]

    init() {}

    /// Creates a draft pre-populated with each configured field's default value.
    init(configuration: FieldConfiguration) {
        for field in configuration.editableFields {
            values[field.id] = field.defaultValue
        }
    }

    /// Creates a draft populated from an existing record for the given configuration.
    init(record: PreloadRecord, configuration: FieldConfiguration) {
        serialNumber = record.serialNumber
        deviceType = PreloadDeviceType(jamfValue: record.deviceType)
        for field in configuration.editableFields {
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
        configuration.editableFields.allSatisfy { field in
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

        var standardValues: [String: String] = [:]
        var extensionAttributes: [(name: String, value: String)] = []

        for field in configuration.editableFields {
            let value = value(for: field)

            if field.isRequired, value.isEmpty {
                throw JamfAppError.validation("\(field.displayName) is required.")
            }

            guard value.isEmpty == false else {
                continue
            }

            switch field.kind {
            case .standard:
                standardValues[field.key] = value
            case .extensionAttribute:
                extensionAttributes.append((name: field.key, value: value))
            }
        }

        return PreloadSubmission(
            serialNumber: serialNumber,
            deviceType: deviceType.rawValue,
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
