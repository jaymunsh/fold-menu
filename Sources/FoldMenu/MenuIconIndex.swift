import AppKit

/// Icon-only reuse for one scan. Never stores AX elements or geometry.
struct MenuIconIndex {
    private var icons: [String: NSImage] = [:]

    init(_ previous: [(id: String, icon: NSImage)]) {
        for entry in previous where icons[entry.id] == nil {
            icons[entry.id] = entry.icon
        }
    }

    func icon(for id: String) -> NSImage? { icons[id] }
}
