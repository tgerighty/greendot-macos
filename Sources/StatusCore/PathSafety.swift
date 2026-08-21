import Foundation

public enum PathSafety {
    public static func contained(_ url: URL, under root: URL) -> URL? {
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let filePath = file.path
        let basePath = base.path
        if filePath == basePath { return file }
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return file
    }

    public static func isPathComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}
