import Foundation

enum JamfAppError: LocalizedError {
    case validation(String)
    case configuration(String)
    case keychain(String)
    case network(String)
    case http(statusCode: Int, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message),
             let .configuration(message),
             let .keychain(message),
             let .network(message),
             let .invalidResponse(message):
            return message
        case let .http(statusCode, message):
            return "\(message)\nHTTP status: \(statusCode)"
        }
    }
}
