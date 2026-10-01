import CoreGraphics
import Foundation

/// One WindowServer read for one verification sample. Create a new snapshot
/// after every await; never cache it across movement or recovery samples.
struct MenuWindowSnapshot {
    struct Host {
        let pid: pid_t
        let window: CGWindowID
        let visible: Bool
        let frame: CGRect
    }

    private let windows: [[String: Any]]

    init(readWindows: () -> [[String: Any]] = {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    }) {
        windows = readWindows()
    }

    func host(at point: CGPoint) -> Host? {
        var matches: [Host] = []
        for entry in windows {
            guard entry[kCGWindowLayer as String] as? Int == 25,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.height < 80, frame.contains(point),
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let window = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            matches.append(Host(pid: pid.int32Value, window: window.uint32Value,
                                visible: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                frame: frame))
        }
        return matches.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    func host(windowID: CGWindowID) -> Host? {
        // The complete list includes offscreen hosted windows on macOS 26;
        // optionIncludingWindow does not reliably return them.
        guard let entry = windows.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }),
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let window = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
        return Host(pid: pid.int32Value, window: window.uint32Value,
                    visible: entry[kCGWindowIsOnscreen as String] as? Bool ?? false, frame: frame)
    }

    func statusHosts() -> [Host] {
        windows.compactMap { entry -> Host? in
            guard entry[kCGWindowLayer as String] as? Int == 25,
                  let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0, frame.height > 0, frame.height <= 50,
                  let number = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
            return Host(pid: pid.int32Value, window: number.uint32Value,
                        visible: entry[kCGWindowIsOnscreen as String] as? Bool ?? false, frame: frame)
        }
    }

    func statusWindowFingerprint() -> Set<String> {
        let layer = Int(CGWindowLevelForKey(.statusWindow))
        return Set(windows.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == layer,
                  let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 0,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite else { return nil }
            return StatusWindowFingerprint.key(windowID: number.uint32Value, frame: frame)
        })
    }
}
