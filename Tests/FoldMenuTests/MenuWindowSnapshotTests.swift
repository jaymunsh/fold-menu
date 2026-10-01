import CoreGraphics
import Foundation

enum MenuWindowSnapshotTests {
    private static func window(_ id: UInt32, pid: Int32 = 1234, frame: CGRect,
                               layer: Int = 25, visible: Bool = true) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowOwnerPID as String: NSNumber(value: pid),
         kCGWindowBounds as String: frame.dictionaryRepresentation,
         kCGWindowLayer as String: layer,
         kCGWindowIsOnscreen as String: visible,
         kCGWindowOwnerName as String: "Snapshot fixture",
         kCGWindowAlpha as String: 1.0,
         kCGWindowMemoryUsage as String: 4096,
         kCGWindowSharingState as String: 1,
         kCGWindowStoreType as String: 2]
    }

    static func run() {
        // Re-reading WindowServer between source and boundary lookups must not
        // mix layouts; a NEW snapshot must still see the next layout.
        let initial = [
            window(1, frame: CGRect(x: 900, y: 0, width: 40, height: 39)),
            window(2, frame: CGRect(x: 940, y: 0, width: 38, height: 39))
        ]
        let changed = [
            window(1, frame: CGRect(x: 600, y: 0, width: 40, height: 39)),
            window(2, frame: CGRect(x: 640, y: 0, width: 38, height: 39))
        ]
        var reads = 0
        let readWindows = { () -> [[String: Any]] in
            reads += 1
            return reads == 1 ? initial : changed
        }
        let first = MenuWindowSnapshot(readWindows: readWindows)
        precondition(first.host(windowID: 1)?.frame.minX == 900)
        precondition(first.host(windowID: 2)?.frame.minX == 940,
                     "Source and boundary must come from the same WindowServer read")
        precondition(first.host(at: CGPoint(x: 950, y: 10))?.window == 2)
        precondition(first.statusHosts().count == 2)
        precondition(first.statusWindowFingerprint() == ["1@900,0,40,39", "2@940,0,38,39"])
        precondition(reads == 1, "Queries within a snapshot must not enumerate WindowServer again")
        let second = MenuWindowSnapshot(readWindows: readWindows)
        precondition(second.host(windowID: 1)?.frame.minX == 600)
        precondition(second.host(windowID: 2)?.frame.minX == 640)
        precondition(reads == 2, "Each new verification sample must read current geometry")

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let fixtures = [
            window(3, frame: CGRect(x: -4000, y: 0, width: 40, height: 39), visible: false),
            window(4, frame: CGRect(x: -3900, y: 0, width: 40, height: 39)),
            window(5, frame: CGRect(x: 900, y: 0, width: 80, height: 39)),
            window(6, frame: CGRect(x: 910, y: 0, width: 20, height: 39)),
            window(7, pid: ownPID, frame: CGRect(x: 910, y: 0, width: 10, height: 39)),
            window(8, frame: CGRect(x: 910, y: 0, width: 8, height: 39), layer: 0),
            window(9, frame: CGRect(x: 1000, y: 0, width: 30, height: 60)),
            window(10, frame: CGRect(x: 1100, y: 0, width: 0, height: 39)),
            [kCGWindowNumber as String: NSNumber(value: 11)]
        ]
        let snapshot = MenuWindowSnapshot(readWindows: { fixtures })
        precondition(snapshot.host(windowID: 3)?.frame.minX == -4000,
                     "Offscreen windows must remain available for return verification")
        precondition(snapshot.host(windowID: 3)?.visible == false)
        precondition(snapshot.host(windowID: 4)?.visible == true,
                     "Keep WindowServer's onscreen flag separate from offscreen geometry")
        precondition(snapshot.host(at: CGPoint(x: 915, y: 10))?.window == 6,
                     "Hit testing must choose the smallest remote status host, excluding our overlays")
        precondition(snapshot.host(at: CGPoint(x: 1005, y: 10))?.window == 9,
                     "Point lookup retains its existing height limit, distinct from statusHosts")
        precondition(Set(snapshot.statusHosts().map(\.window)) == [3, 4, 5, 6, 7])
        precondition(snapshot.host(windowID: 8)?.window == 8,
                     "ID lookup retains its existing unfiltered behavior")
        precondition(snapshot.host(windowID: 11) == nil)
        precondition(snapshot.host(windowID: 999) == nil)
        let empty = MenuWindowSnapshot(readWindows: { [] })
        precondition(empty.host(at: .zero) == nil && empty.statusHosts().isEmpty)
        precondition(empty.statusWindowFingerprint().isEmpty)
        print("PASS: window snapshots share one read, refresh between samples, and retain host lookup rules")
    }
}
