import ApplicationServices

enum NativeMenuPress {
    enum Result: Equatable {
        case requested
        case unsupported
        case failed(AXError)
    }

    static func classify(_ error: AXError) -> Result {
        switch error {
        // A native menu can enter a modal loop without replying before the AX
        // deadline. Do not send a second click and inadvertently close it.
        case .success, .cannotComplete: return .requested
        case .actionUnsupported, .notImplemented: return .unsupported
        default: return .failed(error)
        }
    }

    static func press(_ element: AXUIElement) -> Result {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String] ?? []).contains(kAXPressAction) else { return .unsupported }
        AXUIElementSetMessagingTimeout(element, 0.2)
        defer { AXUIElementSetMessagingTimeout(element, 0.5) }
        return classify(AXUIElementPerformAction(element, kAXPressAction as CFString))
    }
}
