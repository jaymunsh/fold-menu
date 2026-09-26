import CoreGraphics

enum MenuBarMirrorPlacement {
    struct Display {
        let id: UInt32
        let bounds: CGRect
    }

    struct StatusHost {
        let id: UInt32
        let pid: Int32
        let frame: CGRect
    }

    static func displayID(forStatusHost frame: CGRect, among displays: [Display]) -> UInt32? {
        let matches = displays.filter { isReservation(frame, on: $0.bounds) }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// WindowServer moves a menu-bar host just above its screen during auto-hide.
    /// It is still our live host, not a reason to unfold the user's icons.
    static func isTemporarilyHidden(_ frame: CGRect, among displays: [Display]) -> Bool {
        displays.contains { display in
            let bounds = display.bounds
            return !bounds.isEmpty && !bounds.isInfinite && !bounds.isNull
                && frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.width > 1000 && frame.height > 0 && frame.height <= 50
                && frame.maxY >= bounds.minY - 4 && frame.maxY <= bounds.minY + 3
                && frame.minY < bounds.minY - 3 && frame.minY >= bounds.minY - 53
                && frame.maxX > bounds.minX + 20 && frame.maxX <= bounds.maxX + 3
        }
    }

    /// Places one app-owned mirror over the large native status-item reservation
    /// on each active display. The tracked host identifies the real item when
    /// WindowServer exposes more than one plausible reservation on that screen.
    static func frames(
        displays: [Display],
        statusHosts: [StatusHost],
        trackedHostID: UInt32?,
        trackedHostPID: Int32?,
        cocoaPrimaryTop: CGFloat,
        iconSize: CGSize
    ) -> [UInt32: CGRect] {
        guard cocoaPrimaryTop.isFinite,
              iconSize.width.isFinite, iconSize.height.isFinite,
              iconSize.width > 0, iconSize.height > 0 else { return [:] }

        var result: [UInt32: CGRect] = [:]
        for display in displays {
            let bounds = display.bounds
            guard !bounds.isEmpty, !bounds.isInfinite, !bounds.isNull else { continue }

            let candidates = statusHosts.filter { isReservation($0.frame, on: bounds) }

            let host: StatusHost?
            if let trackedHostID, let tracked = candidates.first(where: {
                $0.id == trackedHostID && ($0.pid == trackedHostPID || trackedHostPID == nil)
            }) {
                host = tracked
            } else if let trackedHostPID {
                let ownedCandidates = candidates.filter { $0.pid == trackedHostPID }
                if ownedCandidates.count == 1 {
                    host = ownedCandidates[0]
                } else {
                    // Do not cover a different menu-bar item when the
                    // reservation cannot be attributed to the tracked host.
                    continue
                }
            } else {
                // Without a known owner, only the exact tracked host above is
                // safe to use; geometry alone is not enough to identify it.
                continue
            }
            guard let host else { continue }

            let width = min(iconSize.width, host.frame.maxX - bounds.minX)
            // The glyph is centered by NSButton. Fill this display's status
            // row so a shorter native anchor cannot bottom-align it here.
            let height = host.frame.height
            guard width >= 20, height >= 18 else { continue }

            result[display.id] = CGRect(
                x: host.frame.maxX - width,
                y: cocoaPrimaryTop - host.frame.maxY,
                width: width,
                height: height
            )
        }
        return result
    }

    private static func isReservation(_ frame: CGRect, on bounds: CGRect) -> Bool {
        !bounds.isEmpty && !bounds.isInfinite && !bounds.isNull
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width > 1000 && frame.height > 0 && frame.height <= 50
            && frame.minY >= bounds.minY - 3
            && frame.maxY <= bounds.minY + 48
            && frame.maxX > bounds.minX + 20
            && frame.maxX <= bounds.maxX + 3
    }
}

enum FolderMirrorClickPolicy {
    enum Action: Equatable {
        case open
        case dismiss
        case move
    }

    static func action(panelVisible: Bool, panelDisplayID: UInt32?, clickedDisplayID: UInt32?) -> Action {
        guard panelVisible else { return .open }
        guard let panelDisplayID, let clickedDisplayID else { return .dismiss }
        return panelDisplayID == clickedDisplayID ? .dismiss : .move
    }
}

enum FolderMirrorAppearance {
    /// Match the subdued menu-bar treatment on screens without keyboard focus.
    /// The overlay remains enabled so its click behavior is unchanged.
    static func opacity(displayID: UInt32, activeDisplayID: UInt32?) -> CGFloat {
        guard let activeDisplayID else { return 1 }
        return displayID == activeDisplayID ? 1 : 0.38
    }
}

enum FolderOutsideClickPolicy {
    static func shouldDismiss(eventPoint: CGPoint, panel: CGRect, mirrors: [CGRect]) -> Bool {
        !panel.contains(eventPoint) && !mirrors.contains { $0.contains(eventPoint) }
    }
}
