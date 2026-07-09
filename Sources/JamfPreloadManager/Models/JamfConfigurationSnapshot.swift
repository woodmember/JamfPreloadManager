import Foundation

struct JamfConfigurationSnapshot: Equatable, Sendable {
    var configuration: JamfConfiguration
    var savedServerURLs: [String]
}
