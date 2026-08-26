import Foundation

enum ParserError: Error, Equatable, LocalizedError {
    case notThisProvider
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notThisProvider: return "JSON is not this status-page format"
        case .invalidJSON: return "Status page returned invalid JSON"
        }
    }
}
