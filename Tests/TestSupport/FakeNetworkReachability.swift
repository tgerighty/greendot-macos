import Foundation
import StatusCore

/// Reports whatever `isOnline` the test sets, and fires `onChange` when that value changes.
public final class FakeNetworkReachability: NetworkReachability, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOnline: Bool
    private var storedOnChange: (@Sendable (Bool) -> Void)?

    public init(isOnline: Bool = true) {
        storedOnline = isOnline
    }

    public var isOnline: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnline
        }
        set {
            lock.lock()
            let changed = storedOnline != newValue
            storedOnline = newValue
            let callback = storedOnChange
            lock.unlock()
            if changed {
                callback?(newValue)
            }
        }
    }

    public var onChange: (@Sendable (Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnChange
        }
        set {
            lock.lock()
            storedOnChange = newValue
            lock.unlock()
        }
    }

    public func start() {}

    public func stop() {}
}
