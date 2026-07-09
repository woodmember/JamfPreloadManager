import Foundation

/// How a configured field collects its value in the GUI and CSV templates.
enum FieldInputType: String, Codable, CaseIterable, Sendable {
    case freeText
    case list

    var title: String {
        switch self {
        case .freeText:
            "Free Text"
        case .list:
            "Choose From List"
        }
    }
}

/// The standard, non-extension-attribute fields exposed by the Jamf
/// `api/v2/inventory-preload/records` schema. Each maps a camelCase API key to a
/// human-facing CSV header (the headers Jamf itself uses in its template) plus a
/// set of normalized aliases used when matching imported CSV columns.
enum StandardPreloadField: String, CaseIterable, Codable, Sendable {
    case serialNumber
    case deviceType
    case username
    case fullName
    case emailAddress
    case phoneNumber
    case position
    case department
    case building
    case room
    case poNumber
    case poDate
    case warrantyExpiration
    case appleCareId
    case purchasePrice
    case lifeExpectancy
    case purchasingAccount
    case purchasingContact
    case leaseExpiration
    case barCode1
    case barCode2
    case assetTag
    case vendor

    /// The camelCase key used in the Jamf JSON API payload.
    var apiKey: String { rawValue }

    /// The title-case header Jamf uses in its CSV template. Doubles as the GUI label.
    var csvHeader: String {
        switch self {
        case .serialNumber: "Serial Number"
        case .deviceType: "Device Type"
        case .username: "Username"
        case .fullName: "Full Name"
        case .emailAddress: "Email Address"
        case .phoneNumber: "Phone Number"
        case .position: "Position"
        case .department: "Department"
        case .building: "Building"
        case .room: "Room"
        case .poNumber: "PO Number"
        case .poDate: "PO Date"
        case .warrantyExpiration: "Warranty Expiration"
        case .appleCareId: "Apple Care ID"
        case .purchasePrice: "Purchase Price"
        case .lifeExpectancy: "Life Expectancy"
        case .purchasingAccount: "Purchasing Account"
        case .purchasingContact: "Purchasing Contact"
        case .leaseExpiration: "Lease Expiration"
        case .barCode1: "Bar Code 1"
        case .barCode2: "Bar Code 2"
        case .assetTag: "Asset Tag"
        case .vendor: "Vendor"
        }
    }

    /// Extra normalized header forms accepted when importing CSV files.
    var aliases: Set<String> {
        switch self {
        case .serialNumber: ["serial", "serialno", "serialnumber"]
        case .deviceType: ["devicetype", "type"]
        case .username: ["user", "username"]
        case .fullName: ["fullname", "name"]
        case .emailAddress: ["email", "emailaddress"]
        case .phoneNumber: ["phone", "phonenumber"]
        case .poNumber: ["ponumber", "po"]
        case .poDate: ["podate"]
        case .warrantyExpiration: ["warranty", "warrantyexpiration"]
        case .appleCareId: ["applecare", "applecareid"]
        case .purchasePrice: ["purchaseprice", "price"]
        case .lifeExpectancy: ["lifeexpectancy"]
        case .purchasingAccount: ["purchasingaccount"]
        case .purchasingContact: ["purchasingcontact"]
        case .leaseExpiration: ["lease", "leaseexpiration"]
        case .barCode1: ["barcode1"]
        case .barCode2: ["barcode2"]
        case .assetTag: ["assettag", "asset"]
        default: []
        }
    }

    /// Standard fields a user can enable/disable in Settings. Serial Number is
    /// always implicitly present and required, so it is excluded here.
    static var configurable: [StandardPreloadField] {
        allCases.filter { $0 != .serialNumber }
    }
}

/// A single field the app collects, either a standard Jamf field or a
/// user-defined extension attribute. Drives the GUI and CSV columns.
struct PreloadField: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case standard
        case extensionAttribute
    }

    var id: String
    var kind: Kind
    /// API key for standard fields; extension attribute name for EAs.
    var key: String
    /// GUI label and CSV column header.
    var displayName: String
    var inputType: FieldInputType
    var listOptions: [String]
    var allowsCustomEntry: Bool
    var isRequired: Bool
    var defaultValue: String

    init(
        id: String,
        kind: Kind,
        key: String,
        displayName: String,
        inputType: FieldInputType = .freeText,
        listOptions: [String] = [],
        allowsCustomEntry: Bool = false,
        isRequired: Bool = false,
        defaultValue: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.displayName = displayName
        self.inputType = inputType
        self.listOptions = listOptions
        self.allowsCustomEntry = allowsCustomEntry
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }

    static func standardID(_ field: StandardPreloadField) -> String {
        "std:\(field.rawValue)"
    }

    static func extensionAttributeID(_ name: String) -> String {
        "ea:\(name)"
    }

    static func standard(
        _ field: StandardPreloadField,
        inputType: FieldInputType = .freeText,
        listOptions: [String] = [],
        allowsCustomEntry: Bool = false,
        isRequired: Bool = false,
        defaultValue: String = ""
    ) -> PreloadField {
        PreloadField(
            id: standardID(field),
            kind: .standard,
            key: field.apiKey,
            displayName: field.csvHeader,
            inputType: inputType,
            listOptions: listOptions,
            allowsCustomEntry: allowsCustomEntry,
            isRequired: isRequired,
            defaultValue: defaultValue
        )
    }

    static func extensionAttribute(
        name: String,
        inputType: FieldInputType = .freeText,
        listOptions: [String] = [],
        allowsCustomEntry: Bool = false,
        isRequired: Bool = false,
        defaultValue: String = ""
    ) -> PreloadField {
        PreloadField(
            id: extensionAttributeID(name),
            kind: .extensionAttribute,
            key: name,
            displayName: name,
            inputType: inputType,
            listOptions: listOptions,
            allowsCustomEntry: allowsCustomEntry,
            isRequired: isRequired,
            defaultValue: defaultValue
        )
    }

    var standardField: StandardPreloadField? {
        guard kind == .standard else { return nil }
        return StandardPreloadField(rawValue: key)
    }

    var isDeviceType: Bool {
        standardField == .deviceType
    }

    /// Normalized header forms this field's column can be matched against on import.
    var csvHeaderAliases: Set<String> {
        var aliases: Set<String> = [
            CSVSupport.normalizedHeader(displayName),
            CSVSupport.normalizedHeader(key)
        ]

        if let standardField {
            aliases.formUnion(standardField.aliases)
            aliases.insert(CSVSupport.normalizedHeader(standardField.csvHeader))
        }

        return aliases.filter { $0.isEmpty == false }
    }
}

/// The full set of fields the app is configured to manage.
struct FieldConfiguration: Codable, Equatable, Sendable {
    /// Ordered fields, excluding Serial Number (always implicit + required).
    var fields: [PreloadField]

    init(fields: [PreloadField]) {
        self.fields = fields
    }

    /// Out-of-the-box configuration for a fresh install: just Serial Number
    /// (implicit) plus a Device Type picker defaulting to Computer.
    static var neutralDefault: FieldConfiguration {
        FieldConfiguration(fields: [
            .standard(
                .deviceType,
                inputType: .list,
                listOptions: ["Computer", "Mobile Device", "Unknown"],
                allowsCustomEntry: false,
                isRequired: false,
                defaultValue: AppConstants.deviceType
            )
        ])
    }

    var deviceTypeField: PreloadField? {
        fields.first { $0.isDeviceType }
    }

    func field(withID id: String) -> PreloadField? {
        fields.first { $0.id == id }
    }
}
