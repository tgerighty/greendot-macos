import Foundation
import StatusCore

protocol ToastDelivery: AnyObject {
    @MainActor
    func start()

    @MainActor
    func deliver(_ toast: Toast)

    @MainActor
    func clear(pageID: UUID)
}
