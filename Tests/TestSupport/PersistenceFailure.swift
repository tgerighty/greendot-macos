import Foundation

public func breakPersistence(at configURL: URL) throws {
    try? FileManager.default.removeItem(at: configURL)
    try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
}
