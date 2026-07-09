import Foundation

enum AppConstants {
    static let appName = "Jamf Preload Manager"
    static let appVersion = "0.8p"
    static let executableName = "JamfPreloadManager"
    static let bundleIdentifier = "io.github.woodmember.JamfPreloadManager"
    static let keychainService = bundleIdentifier
    static let legacyKeychainService = "JamfPreloadManager"
    static let defaultJamfURL = "https://yourorg.jamfcloud.com"
    static let currentServerKeychainAccount = "jamf_url"
    static let credentialsKeychainAccountSuffix = ":credentials"
    static let legacyClientIDKeychainAccount = "client_id"
    static let legacyClientSecretKeychainAccount = "client_secret"
    static let savedServersDefaultsKey = "savedJamfServers"

    /// UserDefaults key for the user-editable field configuration (JSON encoded).
    static let userFieldConfigurationKey = "userFieldConfiguration"
    /// Key inspected for a managed (profile-supplied) field configuration.
    static let managedFieldConfigurationKey = "FieldConfiguration"
    /// Optional managed seed for the Jamf server URL (pre-populated, not locked).
    static let managedDefaultServerURLKey = "DefaultServerURL"
    /// Optional managed seed for the Jamf API Client ID (pre-populated, not locked).
    static let managedDefaultClientIDKey = "DefaultClientID"

    /// Sentinel picker tags used by the field editor.
    static let selectPlaceholderChoice = "__SELECT__"
    static let customChoice = "__CUSTOM__"

    /// Fallback device type used when no Device Type field value is supplied.
    static let deviceType = "Computer"

    static func suggestedCSVFilename(date: Date = .now) -> String {
        timestampedFilename(prefix: "inventory_preload", extension: "csv", date: date)
    }

    static func suggestedCSVTemplateFilename(date: Date = .now) -> String {
        timestampedFilename(prefix: "inventory_preload_template", extension: "csv", date: date)
    }

    static func suggestedSerialsOnlyCSVTemplateFilename(date: Date = .now) -> String {
        timestampedFilename(prefix: "inventory_preload_serials_template", extension: "csv", date: date)
    }

    static func suggestedConfigurationProfileFilename(date: Date = .now) -> String {
        timestampedFilename(prefix: "JamfPreloadManager_FieldConfiguration", extension: "mobileconfig", date: date)
    }

    private static func timestampedFilename(prefix: String, extension fileExtension: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(prefix)_\(formatter.string(from: date)).\(fileExtension)"
    }
}
