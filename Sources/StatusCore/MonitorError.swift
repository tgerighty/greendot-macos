import Foundation

public enum MonitorError: Error, Equatable, LocalizedError {
    case pageNotFound(UUID)
    case tokenRequiresReentry

    public var errorDescription: String? {
        switch self {
        case .pageNotFound:
            return "The watched status page could not be found."
        case .tokenRequiresReentry:
            return "The page address changed. Clear or replace its token before saving."
        }
    }
}
