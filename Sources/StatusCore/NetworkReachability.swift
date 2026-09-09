import Foundation
import Network

/// Lets the monitor skip HTTP when the Mac has no route, instead of inferring that from every page failing.
public protocol NetworkReachability: AnyObject, Sendable {
    /// False only when the system reports no route at all. Starts true until the first path update.
    var isOnline: Bool { get }
    /// Called on every change of `isOnline`, with the new value.
    var onChange: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
}

public final class PathNetworkReachability: NetworkReachability, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "greendot.reachability")
    private let lock = NSLock()
    private var started = false
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
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateOnline(path.status != .unsatisfied)
        }
        monitor.start(queue: queue)
    }

    public func stop() {
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
