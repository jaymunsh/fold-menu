import AppKit

enum MenuTransport {
    struct Host {
        let pid: pid_t
        let window: CGWindowID
        let visible: Bool
        let frame: CGRect
    }

    static func host(at point: CGPoint) -> Host? {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
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
                        visible: entry[kCGWindowIsOnscreen as String] as? Bool ?? false, frame: frame))
        }
        // Prefer the smallest containing status window when menu items overlap.
        return matches.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    static func host(windowID: CGWindowID) -> Host? {
        // optionIncludingWindow returns no entry for off-screen hosted status
        // windows on macOS 26. The complete list includes their real bounds.
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let entry = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let pid = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let window = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
        return Host(pid: pid.int32Value, window: window.uint32Value,
                    visible: entry[kCGWindowIsOnscreen as String] as? Bool ?? false, frame: frame)
    }

    enum MoveExpectation {
        case visibleBeside(Host)
        case hidden
    }

    static func statusHosts() -> [Host] {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { entry -> Host? in
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

    @MainActor static func move(_ item: MenuItem, leftOf target: Host, expecting expectation: MoveExpectation, afterTarget: Bool = false) async throws {
        guard let initialFrame = menuElementFrame(item.element),
              let source = host(at: CGPoint(x: initialFrame.midX, y: initialFrame.midY)) else {
            throw PlacementError("이동할 원본 아이콘 창을 찾지 못했어요.")
        }
        guard initialFrame.height <= 44, target.frame.height <= 80 else {
            throw PlacementError("메뉴바 밖으로 이동할 수 있는 좌표를 거부했어요.")
        }

        // Teleport-style menu-bar reorder: both events stay on the menu-bar
        // row, while their window fields identify the source and destination.
        // No vertical drag path is ever emitted.
        guard let liveTarget = host(windowID: target.window) else {
            throw PlacementError("복귀 기준 아이콘이 사라졌습니다. 이동을 중단했어요.")
        }
        let point = CGPoint(x: afterTarget ? liveTarget.frame.maxX : liveTarget.frame.minX, y: initialFrame.midY)
        let cursor = try CursorTransaction()
        defer { cursor.finish() }
        cursor.warp(to: point)

        let eventSource = CGEventSource(stateID: .hidSystemState)
        eventSource?.localEventsSuppressionInterval = 0
        func event(_ type: CGEventType, host: Host, flags: CGEventFlags) throws -> CGEvent {
            guard let value = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else {
                throw PlacementError("아이콘 이동 이벤트를 만들지 못했어요.")
            }
            value.flags = flags
            value.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(host.pid))
            value.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(host.window))
            value.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(host.window))
            value.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: Int64(host.window))
            return value
        }

        let down = try event(.leftMouseDown, host: source, flags: .maskCommand)
        let up = try event(.leftMouseUp, host: liveTarget, flags: [])
        trace("move begin \(item.id) source=\(source.window) target=\(liveTarget.window) point=\(point)")
        // A cancelled task must never leave Command-mouse-down held.
        var released = false
        defer {
            if !released {
                up.post(tap: .cgSessionEventTap)
                up.postToPid(source.pid)
            }
        }
        try await MenuEventDelivery(event: down, pid: source.pid).send()
        // The remote status host acknowledges the input before applying its
        // layout. Releasing on a fixed 25ms timer could end the drag before it
        // started, intermittently leaving the item visible after dismissal.
        var beganMoving = false
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(10))
            if let moved = host(windowID: source.window), moved.frame.origin != source.frame.origin {
                trace("move press source=\(moved.frame) target=\(String(describing: host(windowID: liveTarget.window)?.frame))")
                beganMoving = true
                break
            }
        }
        trace("move press applied=\(beganMoving)")
        try await MenuEventDelivery(event: up, pid: source.pid).send()
        released = true
        try await Task.sleep(nanoseconds: 15_000_000)
        try await MenuEventDelivery(event: up, pid: source.pid).send()

        // Hosted items can move the system pointer again while consuming the
        // release. Keep protection until their layout has settled as well.
        var settling = MenuPlacementSettling()
        let settlingDeadline = ProcessInfo.processInfo.systemUptime + 1.5
        while ProcessInfo.processInfo.systemUptime < settlingDeadline {
            try await Task.sleep(for: .milliseconds(20))
            guard let current = menuElementFrame(item.element),
                  let liveWindow = host(windowID: source.window) else {
                _ = settling.observe(element: nil, window: nil, matchesDestination: false)
                continue
            }
            let matched = switch expectation {
            case .visibleBeside(let boundary):
                isInMenuBarStrip(current) && liveWindow.visible && isInMenuBarStrip(liveWindow.frame)
                    && host(windowID: boundary.window).map {
                        $0.pid == boundary.pid && MenuBarGeometry.isImmediatelyRight(liveWindow.frame, of: $0.frame)
                    } == true
            // WindowServer may keep kCGWindowIsOnscreen=true for an ordered
            // hosted window whose entire frame is outside every display.
            // Verify both independent geometries instead of that stale flag.
            case .hidden: MenuBarGeometry.isParkedOffscreen(current, displays: activeDisplayBounds())
                && MenuBarGeometry.isParkedOffscreen(liveWindow.frame, displays: activeDisplayBounds())
            }
            if settling.observe(element: current, window: liveWindow.frame,
                                matchesDestination: matched && current.origin != initialFrame.origin) {
                trace("move verified \(item.id) \(current) host=\(liveWindow.frame)")
                return
            }
        }
        trace("move unverified source=\(String(describing: host(windowID: source.window)?.frame)) target=\(String(describing: host(windowID: liveTarget.window)?.frame)) ax=\(String(describing: menuElementFrame(item.element)))")
        throw PlacementError("아이콘 이동 결과를 확인하지 못했어요. 추가 이동은 중단했습니다.")
    }

    static func statusWindowFingerprint() -> Set<String> {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
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

    @MainActor static func click(at point: CGPoint, host: Host) async throws {
        // WindowServer performs part of status-item hit testing from the real
        // cursor position, even when the synthesized event contains a point.
        // Keep both positions aligned for the click, then put the user's
        // pointer back where it was.
        let cursor = try CursorTransaction()
        defer { cursor.finish() }
        cursor.warp(to: point)
        try await Task.sleep(nanoseconds: 20_000_000)

        let source = CGEventSource(stateID: .hidSystemState)
        var release: CGEvent?
        defer {
            release?.post(tap: .cgSessionEventTap)
            release?.postToPid(host.pid)
        }
        for type in [CGEventType.leftMouseUp, .leftMouseDown] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
                throw PlacementError("메뉴 클릭 이벤트를 만들지 못했어요.")
            }
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: type == .leftMouseDown ? 1 : 0)
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(host.pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(host.window))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(host.window))
            if type == .leftMouseUp { release = event; continue }
            try await MenuEventDelivery(event: event, pid: host.pid, relayToPID: false).send()
            try await Task.sleep(nanoseconds: 70_000_000)
        }
        if let release { try await MenuEventDelivery(event: release, pid: host.pid, relayToPID: false).send() }
        release = nil
        trace("click sent window=\(host.window) point=\(point)")
    }
}
