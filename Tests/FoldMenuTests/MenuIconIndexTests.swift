import AppKit

enum MenuIconIndexTests {
    static func run() {
        let first = NSImage(size: NSSize(width: 24, height: 24))
        let duplicate = NSImage(size: NSSize(width: 32, height: 32))
        let next = NSImage(size: NSSize(width: 16, height: 16))
        let index = MenuIconIndex([("docker:0", first), ("docker:0", duplicate), ("docker:1", next)])
        precondition(index.icon(for: "docker:0") === first, "Preserve the old first-match lookup, even for duplicate IDs")
        precondition(index.icon(for: "docker:1") === next, "Different menu extras of one app remain distinct")
        precondition(index.icon(for: "missing:0") == nil, "New items must use capture/app-icon fallback")
        let refreshed = MenuIconIndex([("docker:0", next)])
        precondition(refreshed.icon(for: "docker:0") === next, "A new scan must use its current icon input")
        precondition(refreshed.icon(for: "docker:1") == nil, "Removed items must not leak into the next index")
        precondition(MenuIconIndex([]).icon(for: "docker:0") == nil)
        print("PASS: scan icon indexing preserves first match, fallback, and fresh scan inputs")
    }
}
