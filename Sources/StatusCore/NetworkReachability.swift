import Foundation
import Network

/// Lets the monitor skip HTTP when the Mac has no route, instead of inferring that from every page failing.
public protocol NetworkReachability: AnyObject, Sendable {
    /// False only when the system reports no route at all. Starts true until the first path update.
    var isOnline: Bool { get }
    /// Called on every change of `isOnline`, with the new value.
    var onChange: (@Sendable (Bool) -> Void)? { get set }
    /// Starts the path updates. A second call does nothing.
    func start()
    /// Stops the path updates for good. The object cannot monitor again, and a later `start()` does nothing.
    func stop()
}

public final class PathNetworkReachability: NetworkReachability, @unchecked Sendable {
    let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "greendot.reachability")
    private let lock = NSLock()
    private var started = false
    private var stopped = false
    private var storedOnline = true
    private var storedOnChange: (@Sendable (Bool) -> Void)?

    public var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedOnline
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

    public init() {}

    public func start() {
        lock.lock()
        let canStart = !started && !stopped
        started = true
        lock.unlock()
        guard canStart else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateOnline(path.status != .unsatisfied)
        }
        monitor.start(queue: queue)
    }

    /// `NWPathMonitor` cannot start again after `cancel()`, so this class records the stop and refuses a later start.
    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        monitor.cancel()
    }

    private func updateOnline(_ online: Bool) {
        lock.lock()
        let changed = storedOnline != online
        storedOnline = online
        let callback = storedOnChange
        lock.unlock()
        guard changed else { return }
        callback?(online)
    }
}
