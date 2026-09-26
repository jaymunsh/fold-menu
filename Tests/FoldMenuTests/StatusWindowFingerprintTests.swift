import CoreGraphics

enum StatusWindowFingerprintTests {
    static func run() {
        let atRest = CGRect(x: 100, y: 0, width: 38, height: 39)
        let hidden = CGRect(x: 100, y: -39, width: 38, height: 39)
        let resizing = CGRect(x: 100, y: 0, width: 42, height: 39)
        let baseline = StatusWindowFingerprint.key(windowID: 10, frame: atRest)
        precondition(baseline == StatusWindowFingerprint.key(windowID: 10, frame: atRest))
        precondition(baseline != StatusWindowFingerprint.key(windowID: 10, frame: hidden),
                     "Wake settling must notice vertical menu-bar movement")
        precondition(baseline != StatusWindowFingerprint.key(windowID: 10, frame: resizing),
                     "Wake settling must notice status-item width changes")
        print("PASS: status window geometry fingerprint")
    }
}
