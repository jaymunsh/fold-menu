import CoreGraphics

enum MenuBarGeometryTests {
    static func run() {
        let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        precondition(MenuBarGeometry.contains(CGRect(x: 1254, y: 7.5, width: 36, height: 24), displays: [main]))
        precondition(!MenuBarGeometry.contains(CGRect(x: 1254, y: 80, width: 36, height: 24), displays: [main]))
        let upper = CGRect(x: 0, y: -1080, width: 1728, height: 1080)
        precondition(MenuBarGeometry.contains(CGRect(x: 1200, y: -1077, width: 36, height: 24), displays: [main, upper]))
        precondition(MenuBarGeometry.isParkedOffscreen(CGRect(x: -3700, y: 7.5, width: 36, height: 24), displays: [main]))
        let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        precondition(!MenuBarGeometry.isParkedOffscreen(CGRect(x: -100, y: 7.5, width: 36, height: 24), displays: [main, leftDisplay]))
        precondition(!MenuBarGeometry.isParkedOffscreen(CGRect(x: -20, y: 7.5, width: 36, height: 24), displays: [main]), "Partly visible must not count as hidden")
        precondition(!MenuBarGeometry.isParkedOffscreen(CGRect(x: 900, y: 80, width: 36, height: 24), displays: [main]), "Below the menu bar must never count as a safe return")
        precondition(MenuBarGeometry.isParkedOffscreen(CGRect(x: -3923, y: 0, width: 45, height: 39), displays: [main]), "Hosted status window geometry is authoritative even when WindowServer keeps its onscreen flag set")
        let folder = CGRect(x: -3766, y: 0, width: 5016, height: 39)
        let adjacentHost = CGRect(x: 1250, y: 0, width: 54, height: 39)
        let adjacentAX = CGRect(x: 1249, y: 7.5, width: 55.5, height: 24)
        let nextHost = CGRect(x: 1304, y: 0, width: 47, height: 39)
        precondition(adjacentAX.minX < folder.maxX, "Fixture must reproduce the old AX-filter skip")
        precondition(MenuBarGeometry.isImmediatelyRight(adjacentHost, of: folder))
        precondition(!MenuBarGeometry.isImmediatelyRight(nextHost, of: folder), "One skipped icon must not pass as adjacent")
        precondition(!MenuBarGeometry.isImmediatelyRight(adjacentAX, of: folder), "Never mix AX and host geometry")
        let borrowed = CGRect(x: 1210, y: 0, width: 40, height: 39)
        let shiftedFolder = folder.offsetBy(dx: -40, dy: 0)
        precondition(MenuBarGeometry.isImmediatelyRight(borrowed, of: shiftedFolder), "Verify against the live shifted folder")
        precondition(!MenuBarGeometry.isImmediatelyRight(borrowed, of: folder), "The pre-move folder edge is stale")
        precondition(!MenuBarGeometry.isImmediatelyRight(adjacentHost.offsetBy(dx: 0, dy: -1080), of: folder))
        precondition(!MenuBarGeometry.isImmediatelyRight(.zero, of: folder))
        print("PASS: menu-bar geometry")
    }
}
