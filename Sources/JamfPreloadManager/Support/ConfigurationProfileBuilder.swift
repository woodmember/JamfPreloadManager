import Foundation

/// Serialises a `FieldConfiguration` into a macOS configuration profile
/// (`.mobileconfig`). The profile uses the classic managed-preferences (MCX)
/// payload so that, once installed, the app sees the configuration as a *forced*
/// default under the `FieldConfiguration` key and locks the Fields settings.
enum ConfigurationProfileBuilder {
    static func makeProfileData(
        configuration: FieldConfiguration,
        defaultServerURL: String? = nil,
        defaultClientID: String? = nil,
        organization: String = "Jamf Preload Manager",
        displayName: String = "Jamf Preload Manager – Field Configuration"
    ) throws -> Data {
        // Round-trip the configuration through PropertyListEncoder so the embedded
        // structure exactly matches what PropertyListDecoder expects on load.
        let encoded = try PropertyListEncoder().encode(configuration)
        let configurationObject = try PropertyListSerialization.propertyList(from: encoded, options: [], format: nil)

        // The field configuration locks the Fields settings; the server URL and
        // client ID seeds are only starting points and are not locked in the app.
        var preferenceSettings: [String: Any] = [
            AppConstants.managedFieldConfigurationKey: configurationObject
        ]

        if let serverURL = defaultServerURL?.nilIfBlank {
            preferenceSettings[AppConstants.managedDefaultServerURLKey] = serverURL
        }

        if let clientID = defaultClientID?.nilIfBlank {
            preferenceSettings[AppConstants.managedDefaultClientIDKey] = clientID
        }

        let preferencesPayload: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadVersion": 1,
            "PayloadIdentifier": "\(AppConstants.bundleIdentifier).fieldconfiguration.preferences",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Managed Preferences",
            "PayloadContent": [
                AppConstants.bundleIdentifier: [
                    "Forced": [
                        [
                            "mcx_preference_settings": preferenceSettings
                        ]
                    ]
                ]
            ]
        ]

        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "\(AppConstants.bundleIdentifier).fieldconfiguration",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": displayName,
            "PayloadDescription": "Defines and locks the fields Jamf Preload Manager collects.",
            "PayloadOrganization": organization,
            "PayloadScope": "System",
            "PayloadEnabled": true,
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [preferencesPayload]
        ]

        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
