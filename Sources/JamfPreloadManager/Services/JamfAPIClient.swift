import Foundation
import CryptoKit
import Security

struct JamfAPIClient {
    let configuration: JamfConfiguration
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(configuration: JamfConfiguration) {
        self.init(configuration: configuration, session: Self.makePinnedSession(for: configuration))
    }

    init(configuration: JamfConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func fetchRecord(serial: String) async throws -> PreloadRecord? {
        let normalizedSerial = serial.uppercased().removingAllWhitespace
        guard normalizedSerial.isEmpty == false else {
            throw JamfAppError.validation("Serial number is required.")
        }
        guard normalizedSerial.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw JamfAppError.validation("Serial number contains invalid characters.")
        }

        let url = try makeURL(
            path: "api/v2/inventory-preload/records",
            queryItems: [
                URLQueryItem(name: "filter", value: "serialNumber==\"\(normalizedSerial)\""),
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "1")
            ]
        )

        let (data, response) = try await authorizedRequest(url: url)
        guard response.statusCode == 200 else {
            throw statusError(for: response.statusCode, fallback: "Failed to look up the preload record.")
        }

        let payload = try parseRecordList(from: data)
        guard let firstRecord = payload.first else {
            return nil
        }

        return firstRecord
    }

    func createRecord(from submission: PreloadSubmission) async throws -> PreloadRecord {
        let body = try makeRecordBody(from: submission)
        let url = try makeURL(path: "api/v2/inventory-preload/records")
        let (data, response) = try await authorizedRequest(
            url: url,
            method: "POST",
            body: body,
            contentType: "application/json"
        )

        guard response.statusCode == 201 else {
            throw statusError(for: response.statusCode, fallback: "Failed to create the preload entry.")
        }

        return try await resolveMutationRecord(
            from: data,
            submission: submission,
            fallbackID: nil
        )
    }

    func updateRecord(id: Int, submission: PreloadSubmission) async throws -> PreloadRecord {
        let body = try makeRecordBody(from: submission)
        let url = try makeURL(path: "api/v2/inventory-preload/records/\(id)")
        let (data, response) = try await authorizedRequest(
            url: url,
            method: "PUT",
            body: body,
            contentType: "application/json"
        )

        guard response.statusCode == 200 else {
            throw statusError(for: response.statusCode, fallback: "Failed to update the preload entry.")
        }

        return try await resolveMutationRecord(
            from: data,
            submission: submission,
            fallbackID: id
        )
    }

    func deleteRecord(id: Int) async throws {
        let url = try makeURL(path: "api/v2/inventory-preload/records/\(id)")
        let (_, response) = try await authorizedRequest(url: url, method: "DELETE")

        guard response.statusCode == 200 || response.statusCode == 204 else {
            throw statusError(for: response.statusCode, fallback: "Failed to delete the preload entry.")
        }
    }

    func exportCSV() async throws -> Data {
        let url = try makeURL(path: "api/v2/inventory-preload/csv")
        let (data, response) = try await authorizedRequest(url: url, accept: "text/csv")

        guard response.statusCode == 200 else {
            throw statusError(for: response.statusCode, fallback: "Failed to export the inventory preload CSV.")
        }

        guard data.isEmpty == false else {
            throw JamfAppError.invalidResponse("Jamf returned an empty CSV export.")
        }

        return data
    }

    func importCSV(fileText: String) async throws -> [ResourceLink] {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = multipartCSVBody(fileText: fileText, boundary: boundary)
        let url = try makeURL(path: "api/v2/inventory-preload/csv")
        let (data, response) = try await authorizedRequest(
            url: url,
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        guard response.statusCode == 201 else {
            throw csvImportError(statusCode: response.statusCode, data: data)
        }

        return try decode([ResourceLink].self, from: data)
    }

    func testConnection(storedServerURL: String?) async -> ConnectionTestResult {
        let clientIDFound = configuration.clientID.trimmed.isEmpty == false
        let clientSecretFound = configuration.clientSecret.trimmed.isEmpty == false

        do {
            let token = try await fetchAccessToken()
            let apiURL = try makeURL(
                path: "api/v2/inventory-preload/records",
                queryItems: [
                    URLQueryItem(name: "page", value: "0"),
                    URLQueryItem(name: "page-size", value: "1")
                ]
            )

            let (_, response) = try await performRequest(
                url: apiURL,
                method: "GET",
                accept: "application/json",
                token: token
            )

            let apiStatus: String
            switch response.statusCode {
            case 200:
                apiStatus = "SUCCESS (HTTP 200)"
            case 401:
                apiStatus = "UNAUTHORIZED (HTTP 401)"
            case 403:
                apiStatus = "FORBIDDEN (HTTP 403)"
            default:
                apiStatus = "HTTP \(response.statusCode)"
            }

            return ConnectionTestResult(
                hostnameKey: configuration.hostKey,
                storedServerURL: storedServerURL,
                clientIDFound: clientIDFound,
                clientSecretFound: clientSecretFound,
                tokenStatus: "SUCCESS - token obtained",
                apiStatus: apiStatus
            )
        } catch {
            return ConnectionTestResult(
                hostnameKey: configuration.hostKey,
                storedServerURL: storedServerURL,
                clientIDFound: clientIDFound,
                clientSecretFound: clientSecretFound,
                tokenStatus: "FAILED - \(error.localizedDescription)",
                apiStatus: "Not attempted because authentication failed."
            )
        }
    }

    private func authorizedRequest(
        url: URL,
        method: String = "GET",
        accept: String = "application/json",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let token = try await fetchAccessToken()
        return try await performRequest(
            url: url,
            method: method,
            accept: accept,
            token: token,
            body: body,
            contentType: contentType
        )
    }

    private func fetchAccessToken() async throws -> String {
        let url = try makeURL(path: "api/oauth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_secret", value: configuration.clientSecret)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await execute(request: request)
        guard response.statusCode == 200 else {
            throw statusError(for: response.statusCode, fallback: "Authentication failed.")
        }

        let token = try decode(TokenResponse.self, from: data).accessToken
        guard token.isEmpty == false else {
            throw JamfAppError.invalidResponse("Jamf did not return an access token.")
        }

        return token
    }

    private func performRequest(
        url: URL,
        method: String,
        accept: String,
        token: String,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        return try await execute(request: request)
    }

    private func execute(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAppError.invalidResponse("Jamf returned a non-HTTP response.")
            }

            return (data, httpResponse)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw JamfAppError.network("TLS certificate pinning failed for \(configuration.hostKey).")
            }
            if let error = error as? JamfAppError {
                throw error
            }

            throw JamfAppError.network(error.localizedDescription)
        }
    }

    private static func makePinnedSession(for configuration: JamfConfiguration) -> URLSession {
        let expectedHost = JamfConfiguration.host(from: configuration.normalizedServerURL) ?? configuration.hostKey
        let delegate = TLSPinningDelegate(expectedHost: expectedHost)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.waitsForConnectivity = true
        return URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
    }

    private final class TLSPinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let expectedHost: String
        private let pinsKey: String
        private let defaults: UserDefaults
        private let lock = NSLock()

        init(expectedHost: String, defaults: UserDefaults = .standard) {
            self.expectedHost = expectedHost
            self.pinsKey = "jamf.tlsPin.publicKeyHash.\(expectedHost)"
            self.defaults = defaults
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            guard challenge.protectionSpace.host.caseInsensitiveCompare(expectedHost) == .orderedSame else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let policy = SecPolicyCreateSSL(true, expectedHost as CFString)
            SecTrustSetPolicies(trust, policy)

            guard SecTrustEvaluateWithError(trust, nil) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            guard let publicKey = SecTrustCopyKey(trust),
                  let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let publicKeyHash = Data(SHA256.hash(data: publicKeyData)).base64EncodedString()

            lock.lock()
            let pinnedHash = defaults.string(forKey: pinsKey)
            if let pinnedHash {
                let matches = pinnedHash == publicKeyHash
                lock.unlock()
                if matches {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
                return
            }

            defaults.set(publicKeyHash, forKey: pinsKey)
            lock.unlock()
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = URL(string: configuration.normalizedServerURL) else {
            throw JamfAppError.configuration("The saved Jamf server URL is invalid.")
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw JamfAppError.configuration("Unable to create a Jamf API URL.")
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw JamfAppError.configuration("Unable to create a valid Jamf API URL.")
        }

        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw JamfAppError.invalidResponse("Jamf returned a response that could not be decoded.")
        }
    }

    private func statusError(for statusCode: Int, fallback: String) -> JamfAppError {
        switch statusCode {
        case 401:
            return .http(
                statusCode: statusCode,
                message: "Authentication failed. Update the saved Jamf Client ID or Client Secret."
            )
        case 403:
            return .http(
                statusCode: statusCode,
                message: "Authenticated successfully, but Jamf denied access to this action."
            )
        default:
            return .http(statusCode: statusCode, message: fallback)
        }
    }

    private func csvImportError(statusCode: Int, data: Data) -> JamfAppError {
        if statusCode == 400, let details = try? decode(CSVImportErrorResponse.self, from: data), details.errors.isEmpty == false {
            let preview = details.errors.prefix(5).map { item in
                var parts = ["line \(item.line)"]
                if let serialNumber = item.serialNumber?.nilIfBlank {
                    parts.append("serial \(serialNumber)")
                }
                if let field = item.field?.nilIfBlank {
                    parts.append(field)
                }
                if let description = item.description?.nilIfBlank {
                    parts.append(description)
                }
                return parts.joined(separator: ": ")
            }
            .joined(separator: "\n")

            return .http(
                statusCode: statusCode,
                message: "Jamf rejected the CSV upload.\n\(preview)"
            )
        }

        if let responseText = responseText(from: data) {
            switch statusCode {
            case 401:
                return .http(
                    statusCode: statusCode,
                    message: "Jamf rejected the CSV upload request because the token was not accepted.\n\(responseText)"
                )
            case 403:
                return .http(
                    statusCode: statusCode,
                    message: "Jamf accepted the login but blocked this CSV upload request.\n\(responseText)"
                )
            case 415:
                return .http(
                    statusCode: statusCode,
                    message: "Jamf rejected the CSV upload format.\n\(responseText)"
                )
            default:
                break
            }
        }

        return statusError(for: statusCode, fallback: "Failed to import the inventory preload CSV.")
    }

    private func responseText(from data: Data) -> String? {
        guard data.isEmpty == false else {
            return nil
        }

        let rawText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return rawText?.nilIfBlank
    }

    private func multipartCSVBody(fileText: String, boundary: String) -> Data {
        var data = Data()
        let lines = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"file\"; filename=\"inventory-preload.csv\"",
            "Content-Type: text/csv; charset=utf-8",
            "",
            fileText,
            "--\(boundary)--",
            ""
        ]

        for line in lines {
            data.append(Data(line.utf8))
            data.append(Data("\r\n".utf8))
        }

        return data
    }

    private func parseRecordList(from data: Data) throws -> [PreloadRecord] {
        let json = try parseJSON(data)

        if let dictionary = json as? [String: Any] {
            if let results = dictionary["results"] as? [Any] {
                return try results.compactMap { item in
                    guard let record = recordDictionary(from: item) else {
                        return nil
                    }

                    return try parseRecord(from: record)
                }
            }

            if let record = recordDictionary(from: dictionary) {
                return [try parseRecord(from: record)]
            }
        }

        if let array = json as? [Any] {
            return try array.compactMap { item in
                guard let record = recordDictionary(from: item) else {
                    return nil
                }

                return try parseRecord(from: record)
            }
        }

        throw JamfAppError.invalidResponse("Jamf returned an unexpected preload record list.")
    }

    private func resolveMutationRecord(
        from data: Data,
        submission: PreloadSubmission,
        fallbackID: Int?
    ) async throws -> PreloadRecord {
        if let record = try? parseRecord(from: data) {
            return record
        }

        let acknowledgedID = (try? parseMutationAcknowledgement(from: data)) ?? fallbackID

        if let refreshedRecord = try await fetchRecord(serial: submission.serialNumber) {
            return refreshedRecord
        }

        guard let resolvedID = acknowledgedID else {
            throw JamfAppError.invalidResponse("Jamf acknowledged the change, but the app could not load the resulting preload record.")
        }

        var extensionAttributes: [String: String] = [:]
        for attribute in submission.extensionAttributes {
            extensionAttributes[attribute.name] = attribute.value
        }

        return PreloadRecord(
            id: resolvedID,
            serialNumber: submission.serialNumber,
            deviceType: submission.deviceType,
            standardValues: submission.standardValues,
            extensionAttributes: extensionAttributes
        )
    }

    private func parseRecord(from data: Data) throws -> PreloadRecord {
        let json = try parseJSON(data)

        if let dictionary = recordDictionary(from: json) {
            return try parseRecord(from: dictionary)
        }

        if
            let topLevel = json as? [String: Any],
            let result = topLevel["result"],
            let dictionary = recordDictionary(from: result)
        {
            return try parseRecord(from: dictionary)
        }

        throw JamfAppError.invalidResponse("Jamf returned an unexpected preload record payload.")
    }

    private func parseMutationAcknowledgement(from data: Data) throws -> Int {
        let json = try parseJSON(data)

        if
            let dictionary = json as? [String: Any],
            let id = intValue(dictionary["id"])
        {
            return id
        }

        if
            let dictionary = json as? [String: Any],
            let result = dictionary["result"] as? [String: Any],
            let id = intValue(result["id"])
        {
            return id
        }

        throw JamfAppError.invalidResponse("Jamf returned a mutation response without a record ID.")
    }

    private func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JamfAppError.invalidResponse("Jamf returned a response that could not be decoded.")
        }
    }

    private func recordDictionary(from value: Any) -> [String: Any]? {
        value as? [String: Any]
    }

    private func parseRecord(from dictionary: [String: Any]) throws -> PreloadRecord {
        guard let id = intValue(dictionary["id"]) else {
            throw JamfAppError.invalidResponse("Jamf returned a preload record without an ID.")
        }

        guard let serialNumber = stringValue(dictionary["serialNumber"])?.trimmed.nilIfBlank else {
            throw JamfAppError.invalidResponse("Jamf returned a preload record without a serial number.")
        }

        var standardValues: [String: String] = [:]
        for field in StandardPreloadField.allCases where field != .serialNumber && field != .deviceType {
            if let value = stringValue(dictionary[field.apiKey])?.trimmed.nilIfBlank {
                standardValues[field.apiKey] = value
            }
        }

        var extensionAttributes: [String: String] = [:]
        for attribute in self.extensionAttributes(from: dictionary["extensionAttributes"]) {
            guard let name = stringValue(attribute["name"])?.trimmed.nilIfBlank,
                  let value = stringValue(attribute["value"])?.nilIfBlank else {
                continue
            }
            extensionAttributes[name] = value
        }

        return PreloadRecord(
            id: id,
            serialNumber: serialNumber,
            deviceType: stringValue(dictionary["deviceType"]) ?? AppConstants.deviceType,
            standardValues: standardValues,
            extensionAttributes: extensionAttributes
        )
    }

    private func extensionAttributes(from value: Any?) -> [[String: Any]] {
        if let attributes = value as? [[String: Any]] {
            return attributes
        }

        if let items = value as? [Any] {
            return items.compactMap { $0 as? [String: Any] }
        }

        return []
    }

    private func makeRecordBody(from submission: PreloadSubmission) throws -> Data {
        var payload: [String: Any] = [
            "serialNumber": submission.serialNumber,
            "deviceType": submission.deviceType
        ]

        for (key, value) in submission.standardValues {
            payload[key] = value
        }

        payload["extensionAttributes"] = submission.extensionAttributes.map { attribute in
            ["name": attribute.name, "value": attribute.value]
        }

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw JamfAppError.invalidResponse("Unable to encode the preload record request.")
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmed)
        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let array as [Any]:
            let values = array.compactMap(stringValue)
            return values.isEmpty ? nil : values.joined(separator: ", ")
        default:
            return nil
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct ResourceLink: Decodable {
    let id: String
    let href: String
}

private struct CSVImportErrorResponse: Decodable {
    let httpStatus: Int?
    let errors: [CSVImportErrorItem]
}

private struct CSVImportErrorItem: Decodable {
    let code: String?
    let field: String?
    let description: String?
    let id: String?
    let value: String?
    let serialNumber: String?
    let line: Int
    let fieldSize: Int?
    let deviceType: String?
}

