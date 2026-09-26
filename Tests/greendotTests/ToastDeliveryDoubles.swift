import StatusCore
import UserNotifications
@testable import greendot

final class RecordingPersistentToastPresenter: PersistentToastPresenter {
    var presented: [Toast] = []
    var updated: [Toast] = []
    var cleared: [UUID] = []

    func present(_ toast: Toast) {
        presented.append(toast)
    }

    func update(_ toast: Toast) {
        updated.append(toast)
    }

    func clear(pageID: UUID) {
        cleared.append(pageID)
    }
}

/// Used only by main-actor tests and completes every callback synchronously.
final class RecordingUserNotificationCenter: UserNotificationCenterClient, @unchecked Sendable {
    var calls: [String] = []
    var authorizationOptions: UNAuthorizationOptions = []
    var addedRequests: [UNNotificationRequest] = []
    var deliveredRequests: [UNNotificationRequest] = []
    var pendingRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [[String]] = []
    var removedPendingIdentifiers: [[String]] = []

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        calls.append("authorization")
        authorizationOptions = options
        completion(true, nil)
    }

    func add(_ request: UNNotificationRequest) {
        calls.append("add")
        addedRequests.append(request)
    }

    func getDeliveredRequests(
        completion: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        calls.append("delivered")
        completion(deliveredRequests)
    }

    func getPendingNotificationRequests(
        completion: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        calls.append("pending")
        completion(pendingRequests)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        calls.append("remove")
        removedIdentifiers.append(identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        calls.append("removePending")
        removedPendingIdentifiers.append(identifiers)
    }
}
