import CoreGraphics

enum FolderAnchorTrackingTests {
    static func run() {
        typealias Window = FolderAnchorTracking.Window
        let small = Window(id: 41, pid: 100, frame: CGRect(x: 1212, y: 0, width: 38, height: 39))
        let spacer = Window(id: 41, pid: 100, frame: CGRect(x: -3766, y: 0, width: 5016, height: 39))
        let other = Window(id: 42, pid: 200, frame: spacer.frame)
        var tracker = FolderAnchorTracking()
        tracker.begin(host: small)
        precondition(tracker.resolve(reportedFrame: small.frame, candidates: [spacer, other]) == spacer,
                     "A stale 38pt AppKit proxy must not lose the known 5016pt host")
        precondition(tracker.resolve(reportedFrame: nil, candidates: [spacer]) == spacer,
                     "A temporarily missing AppKit proxy must not discard a valid live host")
        let moved = Window(id: 41, pid: 100, frame: CGRect(x: -4800, y: 0, width: 6000, height: 39))
        precondition(tracker.resolve(reportedFrame: small.frame, candidates: [moved]) == moved,
                     "Real host movement/resizing must not depend on proxy geometry")
        tracker.begin(host: small)
        precondition(tracker.resolve(reportedFrame: spacer.frame, candidates: [small, other]) == nil,
                     "Wait for our host to resize instead of borrowing another app's spacer")
        precondition(tracker.resolve(reportedFrame: small.frame, candidates: [other]) == nil)
        let reused = Window(id: 41, pid: 999, frame: spacer.frame)
        precondition(tracker.resolve(reportedFrame: small.frame, candidates: [reused]) == nil,
                     "A reused window ID from a different process is not our cached host")
        tracker.begin(host: nil)
        precondition(tracker.resolve(reportedFrame: spacer.frame, candidates: [spacer, other]) == nil,
                     "Ambiguous geometry must remain unresolved")
        precondition(tracker.resolve(reportedFrame: spacer.frame, candidates: [spacer]) == spacer)
        let replacement = Window(id: 43, pid: 101, frame: spacer.frame)
        precondition(tracker.resolve(reportedFrame: spacer.frame, candidates: [replacement]) == replacement,
                     "Recreated host can be reacquired by unique reported geometry")
        let invalid = Window(id: 43, pid: 101, frame: CGRect(x: 0, y: 0, width: 5016, height: 500))
        precondition(tracker.resolve(reportedFrame: spacer.frame, candidates: [invalid]) == nil)

        tracker.begin(host: nil)
        for _ in 0..<100 { precondition(!tracker.shouldFailOpen(at: 10)) }
        precondition(!tracker.shouldFailOpen(at: 11.99))
        precondition(tracker.shouldFailOpen(at: 12))
        tracker.begin(host: nil)
        precondition(!tracker.shouldFailOpen(at: 20))
        tracker.deferFailOpen(until: 35)
        precondition(!tracker.shouldFailOpen(at: 34.99), "Wake recovery must suppress fail-open during the WindowServer relaunch grace period")
        precondition(tracker.shouldFailOpen(at: 35), "A persistently missing anchor may still fail open after the wake grace period")
        tracker.begin(host: small)
        precondition(!tracker.shouldFailOpen(at: 13), "Retry must not inherit the previous failure deadline")
        tracker.found()
        precondition(!tracker.shouldFailOpen(at: 20), "A recovered frame clears the failure deadline")
        print("PASS: folder anchor identity, stale proxies, ambiguity, and fresh retry grace period")
    }
}
