import StatusCore

protocol ToastDelivery: AnyObject {
    @MainActor
    func start()

    @MainActor
    func deliver(_ toast: Toast)
}
