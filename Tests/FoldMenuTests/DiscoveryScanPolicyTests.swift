enum DiscoveryScanPolicyTests {
    static func run() {
        var policy = DiscoveryScanPolicy()
        let first: Set<String> = ["window-1"]
        let changed: Set<String> = ["window-1", "window-2"]

        precondition(policy.shouldScan(fingerprint: first, now: 100, trusted: true),
                     "An uninitialized scan must run")
        policy.recordCompletedScan(fingerprint: first, now: 100)
        precondition(!policy.shouldScan(fingerprint: first, now: 105, trusted: true),
                     "An unchanged menu bar should not trigger another AX scan")
        precondition(policy.shouldScan(fingerprint: changed, now: 105, trusted: true),
                     "A newly added status window must trigger a scan")
        policy.recordCompletedScan(fingerprint: changed, now: 106)
        precondition(!policy.shouldScan(fingerprint: changed, now: 110, trusted: true),
                     "The changed layout should become the new baseline")
        policy.recordCompletedScan(fingerprint: first, now: 100)
        precondition(policy.shouldScan(fingerprint: first, now: 110, trusted: true),
                     "The fallback scan must detect AX-only changes")
        precondition(policy.shouldScan(fingerprint: [], now: 105, trusted: true),
                     "An unavailable window snapshot must not suppress discovery")
        precondition(policy.shouldScan(fingerprint: first, now: 105, trusted: false),
                     "Permission changes must continue to be checked")
        precondition(policy.shouldScan(fingerprint: first, now: 99, trusted: true),
                     "A reset monotonic clock must not defer discovery")
        print("PASS: discovery scan scheduling")
    }
}
