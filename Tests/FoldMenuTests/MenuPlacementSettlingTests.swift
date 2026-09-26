import CoreGraphics

enum MenuPlacementSettlingTests {
    static func run() {
        var state = MenuPlacementSettling()
        let ax = CGRect(x: 900, y: 7.5, width: 36, height: 24)
        let host = CGRect(x: 901, y: 0, width: 34, height: 39)
        precondition(!state.observe(element: ax, window: host, matchesDestination: true))
        precondition(!state.observe(element: ax, window: host, matchesDestination: true))
        precondition(state.observe(element: ax, window: host, matchesDestination: true))
        precondition(!state.observe(element: ax, window: host.offsetBy(dx: 2, dy: 0), matchesDestination: true), "A moving host resets settling even if AX has not caught up")
        precondition(!state.observe(element: ax.offsetBy(dx: 2, dy: 0), window: host, matchesDestination: true))
        precondition(!state.observe(element: nil, window: host, matchesDestination: true))
        precondition(!state.observe(element: ax, window: host, matchesDestination: true))
        precondition(!state.observe(element: ax, window: host, matchesDestination: false))
        precondition(!state.observe(element: ax, window: host, matchesDestination: true))
        precondition(!state.observe(element: ax, window: host, matchesDestination: true))
        precondition(state.observe(element: ax, window: host, matchesDestination: true))
        print("PASS: placement settling rejects moving, missing, and wrong-destination frames")
    }
}
