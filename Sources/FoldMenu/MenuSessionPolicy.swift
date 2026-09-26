struct MenuSessionPolicy {
    private(set) var appeared = false
    private var emptySamples = 0

    // App windows (0) and persistent status items (25) cannot hold a menu open.
    static func isPopupLayer(_ layer: Int) -> Bool {
        layer > 0 && layer != 25 && layer <= 101
    }

    mutating func observe(hasPopup: Bool) -> Bool {
        if hasPopup { appeared = true; emptySamples = 0 }
        else if appeared { emptySamples += 1 }
        return emptySamples >= 3
    }
}
