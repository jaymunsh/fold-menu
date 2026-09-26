import CoreGraphics

/// Tracks the WindowServer host, not AppKit's sometimes stale status-item frame.
struct FolderAnchorTracking {
    struct Window: Equatable {
        let id: UInt32
        let pid: Int32
        let frame: CGRect

        var isSpacer: Bool {
            frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite
                && frame.width > 1000 && frame.height > 0 && frame.height <= 50
        }
    }

    private(set) var host: Window?
    private(set) var missingSince: Double?
    private var failOpenDeferredUntil: Double?

    mutating func begin(host: Window?) {
        self.host = host
        missingSince = nil
        failOpenDeferredUntil = nil
    }

    mutating func resolve(reportedFrame: CGRect?, candidates: [Window]) -> Window? {
        if let host, let live = candidates.first(where: { $0.id == host.id && $0.pid == host.pid }) {
            // Resizing is asynchronous. While our own host is still small, do
            // not mistake another app's large spacer for our expanding host.
            guard live.isSpacer else { return nil }
            self.host = live
            return live
        }

        // A host can be recreated by WindowServer. Reacquire only an unambiguous
        // spacer with the reported geometry; a stale small frame proves nothing.
        guard let reportedFrame, reportedFrame.width > 1000 else { return nil }
        let matches = candidates.filter {
            $0.isSpacer && abs($0.frame.width - reportedFrame.width) < 1
                && abs($0.frame.height - reportedFrame.height) < 1
                && abs($0.frame.minY - reportedFrame.minY) < 1
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        host = match
        return match
    }

    mutating func found() {
        missingSince = nil
        failOpenDeferredUntil = nil
    }

    /// Elapsed time, not timer/sample count: multiple callers must not consume
    /// the grace period early, and each new collapse starts with a fresh budget.
    mutating func deferFailOpen(until deadline: Double) {
        failOpenDeferredUntil = max(failOpenDeferredUntil ?? deadline, deadline)
    }

    mutating func shouldFailOpen(at now: Double) -> Bool {
        guard let missingSince else {
            self.missingSince = now
            return false
        }
        guard now >= (failOpenDeferredUntil ?? -.infinity) else { return false }
        return now - missingSince >= 2
    }
}
