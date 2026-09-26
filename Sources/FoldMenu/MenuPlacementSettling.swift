import CoreGraphics

/// Require unchanged AX and hosted-window geometry, not just several samples
/// somewhere in the menu-bar lane. Faster polling must not accept moving frames.
struct MenuPlacementSettling {
    private var lastElement: CGRect?
    private var lastWindow: CGRect?
    private var samples = 0

    mutating func observe(element: CGRect?, window: CGRect?, matchesDestination: Bool) -> Bool {
        guard matchesDestination, let element, let window else {
            lastElement = nil
            lastWindow = nil
            samples = 0
            return false
        }
        samples = lastElement == element && lastWindow == window ? samples + 1 : 1
        lastElement = element
        lastWindow = window
        return samples >= 3
    }
}
