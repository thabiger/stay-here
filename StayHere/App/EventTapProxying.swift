import Core

protocol EventTapProxying: AnyObject {
    func register(_ client: any CGEventTapClient)
    func unregister(_ client: any CGEventTapClient)
    func removeAllClients()
}
