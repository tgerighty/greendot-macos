import Foundation

public final class ControllableLock: NSLocking, @unchecked Sendable {
    private let condition = NSCondition()
    private let wrapped = NSLock()
    private var shouldBlockNextAcquisition = false
    private var acquisitionIsBlocked = false

    public init() {
        // Lock acquisition passes through until a test requests a block.
    }

    public func blockNextAcquisition() {
        condition.lock()
        shouldBlockNextAcquisition = true
        condition.unlock()
    }

    public func waitUntilAcquisitionBlocked(timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !acquisitionIsBlocked {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    public func resumeBlockedAcquisition() {
        condition.lock()
        shouldBlockNextAcquisition = false
        acquisitionIsBlocked = false
        condition.broadcast()
        condition.unlock()
    }

    public func lock() {
        condition.lock()
        if shouldBlockNextAcquisition {
            shouldBlockNextAcquisition = false
            acquisitionIsBlocked = true
            condition.broadcast()
            while acquisitionIsBlocked {
                condition.wait()
            }
        }
        condition.unlock()
        wrapped.lock()
    }

    public func unlock() {
        wrapped.unlock()
    }
}
