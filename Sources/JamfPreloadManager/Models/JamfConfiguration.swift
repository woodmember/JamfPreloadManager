import Foundation

struct JamfConfiguration: Equatable, Sendable {
    var serverURL: String = AppConstants.defaultJamfURL
    var clientID: String = ""
    var clientSecret: String = ""

    var normalizedServerURL: String {
        Self.normalizeURLString(serverURL) ?? serverURL.trimmed
    }

    var hostKey: String {
        Self.host(from: normalizedServerURL) ?? normalizedServerURL
    }

    var hasCredentials: Bool {
        clientID.trimmed.isEmpty == false && clientSecret.trimmed.isEmpty == false
    }

    var isComplete: Bool {
        Self.normalizeURLString(serverURL) != nil && hasCredentials
    }

    func validated() throws -> JamfConfiguration {
        guard let normalizedURL = Self.normalizeURLString(serverURL) else {
            throw JamfAppError.validation("Server URL must begin with https:// and point to a valid Jamf host.")
        }

        guard let clientID = clientID.trimmed.nilIfBlank else {
            throw JamfAppError.validation("Client ID is required.")
        }

        guard let clientSecret = clientSecret.trimmed.nilIfBlank else {
            throw JamfAppError.validation("Client Secret is required.")
        }

        return JamfConfiguration(
            serverURL: normalizedURL,
            clientID: clientID,
            clientSecret: clientSecret
        )
    }

    static func normalizeURLString(_ value: String) -> String? {
        let trimmedValue = value.trimmed
        guard trimmedValue.lowercased().hasPrefix("https://") else {
            return nil
        }

        let normalized = String(trimmedValue.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard let components = URLComponents(string: normalized), components.host != nil else {
            return nil
        }

        return normalized
    }

    static func host(from urlString: String) -> String? {
        URLComponents(string: urlString)?.host
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    var removingAllWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
