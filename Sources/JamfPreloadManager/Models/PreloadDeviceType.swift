import Foundation

/// The kind of device an inventory preload record targets. The raw values are the
/// exact strings the Jamf Pro API and CSV import/export expect for `deviceType`.
enum PreloadDeviceType: String, CaseIterable, Codable, Sendable, Identifiable {
    case computer = "Computer"
    case mobileDevice = "Mobile Device"

    var id: String { rawValue }

    /// GUI label / CSV value.
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .computer: "laptopcomputer"
        case .mobileDevice: "ipad.and.iphone"
        }
    }

    /// Parses a raw Jamf value, defaulting to `.computer` for anything unrecognised.
    init(jamfValue: String?) {
        switch jamfValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mobile device", "mobiledevice", "mobile":
            self = .mobileDevice
        default:
            self = .computer
        }
    }
}
