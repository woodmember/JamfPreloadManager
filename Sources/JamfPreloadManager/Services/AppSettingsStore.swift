import Foundation

struct FieldConfigurationSnapshot: Equatable, Sendable {
    let configuration: FieldConfiguration
    /// True when the configuration was supplied by a managed (profile) source and
    /// therefore must not be edited by the user.
    let isManaged: Bool
}

/// Loads and persists the app's field configuration. A configuration pushed by a
/// managed configuration profile (MDM) always wins and locks out user edits; other
/// wise the user's own configuration is read from (and written to) `UserDefaults`.
struct AppSettingsStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FieldConfigurationSnapshot {
        if let managed = loadManagedConfiguration() {
            return FieldConfigurationSnapshot(configuration: managed, isManaged: true)
        }

        return FieldConfigurationSnapshot(configuration: loadUserConfiguration(), isManaged: false)
    }

    func save(_ configuration: FieldConfiguration) throws {
        guard loadManagedConfiguration() == nil else {
            throw JamfAppError.configuration(
                "The field configuration is managed by your organization and cannot be changed here."
            )
        }

        do {
            let data = try JSONEncoder().encode(configuration)
            defaults.set(data, forKey: AppConstants.userFieldConfigurationKey)
        } catch {
            throw JamfAppError.configuration("Unable to save the field configuration.")
        }
    }

    /// Optional managed seed for the Jamf server URL. Pre-populated for the user
    /// but not locked, so users may still change and save their own value.
    func managedDefaultServerURL() -> String? {
        defaults.string(forKey: AppConstants.managedDefaultServerURLKey)?.nilIfBlank
    }

    /// Optional managed seed for the Jamf API Client ID (pre-populated, not locked).
    func managedDefaultClientID() -> String? {
        defaults.string(forKey: AppConstants.managedDefaultClientIDKey)?.nilIfBlank
    }

    /// Reads a configuration forced by a managed preferences profile, if present.
    func loadManagedConfiguration() -> FieldConfiguration? {
        guard defaults.objectIsForced(forKey: AppConstants.managedFieldConfigurationKey),
              let object = defaults.object(forKey: AppConstants.managedFieldConfigurationKey) else {
            return nil
        }

        return decodePropertyList(object)
    }

    /// Decodes a `FieldConfiguration` from a raw property-list object (used for both
    /// managed preferences and validating exported profiles).
    func decodePropertyList(_ object: Any) -> FieldConfiguration? {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            return try PropertyListDecoder().decode(FieldConfiguration.self, from: data)
        } catch {
            return nil
        }
    }

    private func loadUserConfiguration() -> FieldConfiguration {
        guard let data = defaults.data(forKey: AppConstants.userFieldConfigurationKey) else {
            return .neutralDefault
        }

        return (try? JSONDecoder().decode(FieldConfiguration.self, from: data)) ?? .neutralDefault
    }
}
