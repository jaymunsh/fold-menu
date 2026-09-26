import ApplicationServices

enum NativeMenuPressTests {
    static func run() {
        precondition(NativeMenuPress.classify(.success) == .requested)
        precondition(NativeMenuPress.classify(.cannotComplete) == .requested, "AX timeout may mean a modal menu is already open; never double-click")
        precondition(NativeMenuPress.classify(.actionUnsupported) == .unsupported)
        precondition(NativeMenuPress.classify(.notImplemented) == .unsupported)
        precondition(NativeMenuPress.classify(.invalidUIElement) == .failed(.invalidUIElement), "A dead element must not trigger a blind pointer click")
        print("PASS: native menu press avoids duplicate clicks on ambiguous replies")
    }
}
