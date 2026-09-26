import Foundation

struct DiscoveryScanPolicy {
    private let fallbackInterval: TimeInterval = 10
    private var lastFingerprint: Set<String>?
    private var lastScanTime: TimeInterval?

    func shouldScan(fingerprint: Set<String>, now: TimeInterval, trusted: Bool) -> Bool {
        guard trusted, !fingerprint.isEmpty,
              let lastFingerprint, let lastScanTime else { return true }
        return fingerprint != lastFingerprint || now < lastScanTime
            || now - lastScanTime >= fallbackInterval
    }

    mutating func recordCompletedScan(fingerprint: Set<String>, now: TimeInterval) {
        lastFingerprint = fingerprint
        lastScanTime = now
    }
}
