import StatusCore

protocol ToastDelivery: AnyObject {
    func start()
    func deliver(_ toast: Toast)
}
