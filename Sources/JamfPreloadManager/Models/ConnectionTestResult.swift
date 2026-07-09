struct ConnectionTestResult: Sendable {
    let hostnameKey: String
    let storedServerURL: String?
    let clientIDFound: Bool
    let clientSecretFound: Bool
    let tokenStatus: String
    let apiStatus: String

    var detailText: String {
        """
        Server URL: \(storedServerURL ?? "(using default)")
        Keychain hostname key: \(hostnameKey)

        Client ID: \(clientIDFound ? "Stored" : "Not found")
        Client Secret: \(clientSecretFound ? "Stored" : "Not found")

        Auth Token: \(tokenStatus)
        API Connectivity: \(apiStatus)
        """
    }
}
