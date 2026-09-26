enum MenuSessionTests {
    static func run() {
        precondition(!MenuSessionPolicy.isPopupLayer(0), "App windows must not keep the menu locked")
        precondition(!MenuSessionPolicy.isPopupLayer(25), "Persistent hosted status items are not menus")
        precondition(MenuSessionPolicy.isPopupLayer(101), "Native popup menu must be observed")
        var tracker = MenuSessionPolicy()
        for _ in 0..<30 { precondition(!tracker.observe(hasPopup: false), "Missing popup is not a successful click") }
        precondition(!tracker.observe(hasPopup: true))
        precondition(!tracker.observe(hasPopup: false))
        precondition(!tracker.observe(hasPopup: true), "A submenu transition must not trigger a premature return")
        precondition(!tracker.observe(hasPopup: false))
        precondition(!tracker.observe(hasPopup: false))
        precondition(tracker.observe(hasPopup: false), "Return after menu dismisses and settles")
        print("PASS: native menu lifecycle and persistent-window regression")
    }
}
