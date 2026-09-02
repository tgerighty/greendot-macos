import Foundation
import StatusCore
@testable import greendot

final class InMemoryToastDelivery: ToastDelivery {
    private let lock = NSLock()
    private var storedStartCount = 0
    private var storedToasts: [Toast] = []

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStartCount
    }

    var toasts: [Toast] {
        lock.lock()
        defer { lock.unlock() }
        return storedToasts
    }

    func start() {
        lock.lock()
        storedStartCount += 1
        lock.unlock()
    }

    func deliver(_ toast: Toast) {
        lock.lock()
        storedToasts.append(toast)
        lock.unlock()
    }

    func clear(pageID _: UUID) {}
}
