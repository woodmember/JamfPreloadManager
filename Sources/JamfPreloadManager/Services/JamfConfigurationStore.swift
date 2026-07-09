import Foundation

struct JamfConfigurationStore: Sendable {
    let keychain: KeychainStore
    let legacyKeychain: KeychainStore?

    init(keychain: KeychainStore, legacyKeychain: KeychainStore? = nil) {
        self.keychain = keychain
        self.legacyKeychain = legacyKeychain
    }

    func load() throws -> JamfConfigurationSnapshot {
        let activeServerURL = try currentServerURL()

        let savedServerURLs = normalizedSavedServerURLs(including: activeServerURL)
        saveSavedServerURLs(savedServerURLs)

        return JamfConfigurationSnapshot(
            configuration: try configuration(for: activeServerURL),
            savedServerURLs: savedServerURLs
        )
    }

    func addServer(serverURL: String) throws -> JamfConfigurationSnapshot {
        let normalizedURL = try validatedServerURL(serverURL)
        var savedServerURLs = normalizedSavedServerURLs(including: normalizedURL)

        if savedServerURLs.contains(normalizedURL) == false {
            savedServerURLs.append(normalizedURL)
        }

        savedServerURLs = normalizeServerURLs(savedServerURLs, fallback: normalizedURL)
        saveSavedServerURLs(savedServerURLs)
        try keychain.write(account: AppConstants.currentServerKeychainAccount, value: normalizedURL)

        return JamfConfigurationSnapshot(
            configuration: try configuration(for: normalizedURL),
            savedServerURLs: savedServerURLs
        )
    }

    func switchServer(to serverURL: String) throws -> JamfConfigurationSnapshot {
        let normalizedURL = try validatedServerURL(serverURL)
        let savedServerURLs = normalizedSavedServerURLs(including: normalizedURL)

        saveSavedServerURLs(savedServerURLs)
        try keychain.write(account: AppConstants.currentServerKeychainAccount, value: normalizedURL)

        return JamfConfigurationSnapshot(
            configuration: try configuration(for: normalizedURL),
            savedServerURLs: savedServerURLs
        )
    }

    func save(
        serverURL: String,
        clientID: String,
        clientSecret: String?,
        existingConfiguration: JamfConfiguration
    ) throws -> JamfConfigurationSnapshot {
        let normalizedURL = try validatedServerURL(serverURL)
        var savedServerURLs = normalizedSavedServerURLs(including: normalizedURL)

        if savedServerURLs.contains(normalizedURL) == false {
            savedServerURLs.append(normalizedURL)
        }

        savedServerURLs = normalizeServerURLs(savedServerURLs, fallback: normalizedURL)

        let hostKey = JamfConfiguration.host(from: normalizedURL) ?? normalizedURL
        let hostChanged = hostKey != existingConfiguration.hostKey

        let savedHostCredentials = try readCredentials(for: hostKey)

        let resolvedClientID =
            clientID.trimmed.nilIfBlank
            ?? (hostChanged ? savedHostCredentials?.clientID.trimmed.nilIfBlank : existingConfiguration.clientID.trimmed.nilIfBlank)

        let resolvedClientSecret =
            clientSecret?.trimmed.nilIfBlank
            ?? (hostChanged ? savedHostCredentials?.clientSecret.trimmed.nilIfBlank : existingConfiguration.clientSecret.trimmed.nilIfBlank)

        guard let resolvedClientID else {
            throw JamfAppError.validation("Client ID is required for this Jamf server.")
        }

        guard let resolvedClientSecret else {
            throw JamfAppError.validation("Client Secret is required for this Jamf server.")
        }

        saveSavedServerURLs(savedServerURLs)
        try keychain.write(account: AppConstants.currentServerKeychainAccount, value: normalizedURL)
        try writeCredentials(
            StoredCredentials(clientID: resolvedClientID, clientSecret: resolvedClientSecret),
            for: hostKey
        )

        return JamfConfigurationSnapshot(
            configuration: JamfConfiguration(
                serverURL: normalizedURL,
                clientID: resolvedClientID,
                clientSecret: resolvedClientSecret
            ),
            savedServerURLs: savedServerURLs
        )
    }

    private func currentServerURL() throws -> String {
        let storedURL = try readMigrating(account: AppConstants.currentServerKeychainAccount)
        return JamfConfiguration.normalizeURLString(storedURL ?? "") ?? defaultServerURL()
    }

    /// The server URL used when nothing is stored yet. Prefers a managed seed
    /// (pushed via a configuration profile) so admins can pre-populate it.
    private func defaultServerURL() -> String {
        if let managed = UserDefaults.standard.string(forKey: AppConstants.managedDefaultServerURLKey),
           let normalized = JamfConfiguration.normalizeURLString(managed) {
            return normalized
        }

        return AppConstants.defaultJamfURL
    }

    private func configuration(for serverURL: String) throws -> JamfConfiguration {
        let normalizedURL = try validatedServerURL(serverURL)
        let hostKey = JamfConfiguration.host(from: normalizedURL) ?? normalizedURL
        let credentials = try readCredentials(for: hostKey)

        return JamfConfiguration(
            serverURL: normalizedURL,
            clientID: credentials?.clientID ?? "",
            clientSecret: credentials?.clientSecret ?? ""
        )
    }

    private func readCredentials(for hostKey: String) throws -> StoredCredentials? {
        if let encodedCredentials = try readMigrating(account: credentialsAccount(for: hostKey))?.trimmed.nilIfBlank {
            return try decodeCredentials(encodedCredentials, for: hostKey)
        }

        return try migrateLegacyCredentialsIfNeeded(for: hostKey)
    }

    private func writeCredentials(_ credentials: StoredCredentials, for hostKey: String) throws {
        let encodedCredentials = try encodeCredentials(credentials, for: hostKey)
        try keychain.write(account: credentialsAccount(for: hostKey), value: encodedCredentials)
        try deleteLegacyCredentialEntries(for: hostKey)
    }

    private func migrateLegacyCredentialsIfNeeded(for hostKey: String) throws -> StoredCredentials? {
        let splitClientID = try readMigrating(account: splitClientIDAccount(for: hostKey))?.trimmed.nilIfBlank
        let splitClientSecret = try readMigrating(account: splitClientSecretAccount(for: hostKey))?.trimmed.nilIfBlank

        if splitClientID != nil || splitClientSecret != nil {
            guard let splitClientID, let splitClientSecret else {
                throw JamfAppError.keychain("Saved keychain credentials for \(hostKey) are incomplete. Re-enter them in Settings.")
            }

            let credentials = StoredCredentials(clientID: splitClientID, clientSecret: splitClientSecret)
            try writeCredentials(credentials, for: hostKey)
            return credentials
        }

        let legacyClientID = try readMigrating(account: AppConstants.legacyClientIDKeychainAccount)?.trimmed.nilIfBlank
        let legacyClientSecret = try readMigrating(account: AppConstants.legacyClientSecretKeychainAccount)?.trimmed.nilIfBlank

        if legacyClientID != nil || legacyClientSecret != nil {
            guard let legacyClientID, let legacyClientSecret else {
                throw JamfAppError.keychain("Legacy keychain credentials are incomplete. Re-enter them in Settings.")
            }

            let credentials = StoredCredentials(clientID: legacyClientID, clientSecret: legacyClientSecret)
            try writeCredentials(credentials, for: hostKey)
            return credentials
        }

        return nil
    }

    private func readMigrating(account: String) throws -> String? {
        if let value = try keychain.read(account: account) {
            return value
        }

        guard let legacyKeychain else {
            return nil
        }

        guard let legacyValue = try legacyKeychain.read(account: account) else {
            return nil
        }

        try? keychain.write(account: account, value: legacyValue)
        try? legacyKeychain.delete(account: account)
        return legacyValue
    }

    private func validatedServerURL(_ value: String) throws -> String {
        guard let normalizedURL = JamfConfiguration.normalizeURLString(value) else {
            throw JamfAppError.validation("Server URL must begin with https:// and point to a valid Jamf host.")
        }

        return normalizedURL
    }

    private func normalizedSavedServerURLs(including activeServerURL: String) -> [String] {
        let storedServerURLs = UserDefaults.standard.stringArray(forKey: AppConstants.savedServersDefaultsKey) ?? []
        return normalizeServerURLs(storedServerURLs, fallback: activeServerURL)
    }

    private func normalizeServerURLs(_ values: [String], fallback: String) -> [String] {
        var uniqueURLs: [String] = []
        var seen = Set<String>()

        for value in values + [fallback] {
            guard let normalizedURL = JamfConfiguration.normalizeURLString(value) else {
                continue
            }

            if seen.insert(normalizedURL).inserted {
                uniqueURLs.append(normalizedURL)
            }
        }

        return uniqueURLs.isEmpty ? [fallback] : uniqueURLs
    }

    private func saveSavedServerURLs(_ values: [String]) {
        UserDefaults.standard.set(values, forKey: AppConstants.savedServersDefaultsKey)
    }

    private func credentialsAccount(for hostKey: String) -> String {
        "\(hostKey)\(AppConstants.credentialsKeychainAccountSuffix)"
    }

    private func splitClientIDAccount(for hostKey: String) -> String {
        "\(hostKey):client_id"
    }

    private func splitClientSecretAccount(for hostKey: String) -> String {
        "\(hostKey):client_secret"
    }

    private func encodeCredentials(_ credentials: StoredCredentials, for hostKey: String) throws -> String {
        do {
            let data = try JSONEncoder().encode(credentials)

            guard let encoded = String(data: data, encoding: .utf8) else {
                throw JamfAppError.keychain("Unable to encode keychain credentials for \(hostKey).")
            }

            return encoded
        } catch let error as JamfAppError {
            throw error
        } catch {
            throw JamfAppError.keychain("Unable to encode keychain credentials for \(hostKey).")
        }
    }

    private func decodeCredentials(_ encodedCredentials: String, for hostKey: String) throws -> StoredCredentials {
        guard let data = encodedCredentials.data(using: .utf8) else {
            throw JamfAppError.keychain("Saved keychain credentials for \(hostKey) are unreadable. Re-enter them in Settings.")
        }

        do {
            return try JSONDecoder().decode(StoredCredentials.self, from: data)
        } catch {
            throw JamfAppError.keychain("Saved keychain credentials for \(hostKey) could not be decoded. Re-enter them in Settings.")
        }
    }

    private func deleteLegacyCredentialEntries(for hostKey: String) throws {
        try keychain.delete(account: splitClientIDAccount(for: hostKey))
        try keychain.delete(account: splitClientSecretAccount(for: hostKey))
        try keychain.delete(account: AppConstants.legacyClientIDKeychainAccount)
        try keychain.delete(account: AppConstants.legacyClientSecretKeychainAccount)

        if let legacyKeychain {
            try? legacyKeychain.delete(account: splitClientIDAccount(for: hostKey))
            try? legacyKeychain.delete(account: splitClientSecretAccount(for: hostKey))
            try? legacyKeychain.delete(account: AppConstants.legacyClientIDKeychainAccount)
            try? legacyKeychain.delete(account: AppConstants.legacyClientSecretKeychainAccount)
        }
    }
}

private struct StoredCredentials: Codable, Sendable {
    let clientID: String
    let clientSecret: String
}
