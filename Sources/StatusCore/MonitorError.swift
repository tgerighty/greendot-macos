import Foundation

public enum MonitorError: Error, Equatable, LocalizedError {
    case pageNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .pageNotFound:
            return "The watched status page could not be found."
        }
    }
}
