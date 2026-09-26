import Foundation
import StatusCore
@testable import greendot

final class InMemoryToastDelivery: ToastDelivery {
    private let lock = NSLock()
    private var storedToasts: [Toast] = []
    private var storedClearedPageIDs: [UUID] = []

    var toasts: [Toast] {
        lock.lock()
        defer { lock.unlock() }
        return storedToasts
    }

    var clearedPageIDs: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return storedClearedPageIDs
    }

    func start() {}

    func deliver(_ toast: Toast) {
        lock.lock()
        storedToasts.append(toast)
        lock.unlock()
    }

    func clear(pageID: UUID) {
        lock.lock()
        storedClearedPageIDs.append(pageID)
        lock.unlock()
    }
}
