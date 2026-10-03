import Foundation

/// Light, dark, or the Mac appearance. `state.json` stores this. `config.json` does not.
public enum InterfaceStyle: String, Codable, Equatable, Sendable {
    case system
    case light
    case dark
}
