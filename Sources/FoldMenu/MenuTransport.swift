import AppKit

enum MenuTransport {
    typealias Host = MenuWindowSnapshot.Host

    static func host(at point: CGPoint) -> Host? {
        MenuWindowSnapshot().host(at: point)
    }

    static func host(windowID: CGWindowID) -> Host? {
        MenuWindowSnapshot().host(windowID: windowID)
    }

    enum MoveExpectation {
        case visibleBeside(Host)
        case hidden
    }

    static func statusHosts() -> [Host] {
        MenuWindowSnapshot().statusHosts()
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
        menuOperationDiagnostics.record("move.begin", detail: "source=\(source.window):\(source.frame) target=\(liveTarget.window):\(liveTarget.frame) ax=\(initialFrame) point=\(point)")
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
            let snapshot = MenuWindowSnapshot()
            if let moved = snapshot.host(windowID: source.window), moved.frame.origin != source.frame.origin {
                trace("move press source=\(moved.frame) target=\(String(describing: snapshot.host(windowID: liveTarget.window)?.frame))")
                beganMoving = true
                break
            }
        }
        trace("move press applied=\(beganMoving)")
        menuOperationDiagnostics.record("move.pressApplied", detail: "applied=\(beganMoving)")
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
            guard let current = menuElementFrame(item.element) else {
                _ = settling.observe(element: nil, window: nil, matchesDestination: false)
                continue
            }
            let snapshot = MenuWindowSnapshot()
            guard let liveWindow = snapshot.host(windowID: source.window) else {
                _ = settling.observe(element: nil, window: nil, matchesDestination: false)
                continue
            }
            let displays = activeDisplayBounds()
            let matched = switch expectation {
            case .visibleBeside(let boundary):
                MenuBarGeometry.contains(current, displays: displays) && liveWindow.visible
                    && MenuBarGeometry.contains(liveWindow.frame, displays: displays)
                    && snapshot.host(windowID: boundary.window).map {
                        $0.pid == boundary.pid && MenuBarGeometry.isImmediatelyRight(liveWindow.frame, of: $0.frame)
                    } == true
            // WindowServer may keep kCGWindowIsOnscreen=true for an ordered
            // hosted window whose entire frame is outside every display.
            // Verify both independent geometries instead of that stale flag.
            case .hidden: MenuBarGeometry.isParkedOffscreen(current, displays: displays)
                && MenuBarGeometry.isParkedOffscreen(liveWindow.frame, displays: displays)
            }
            if settling.observe(element: current, window: liveWindow.frame,
                                matchesDestination: matched && current.origin != initialFrame.origin) {
                trace("move verified \(item.id) \(current) host=\(liveWindow.frame)")
                menuOperationDiagnostics.record("move.verified", detail: "ax=\(current) host=\(liveWindow.frame)")
                return
            }
        }
        let snapshot = MenuWindowSnapshot()
        let finalElement = menuElementFrame(item.element)
        let failureGeometry = "source=\(String(describing: snapshot.host(windowID: source.window)?.frame)) target=\(String(describing: snapshot.host(windowID: liveTarget.window)?.frame)) ax=\(String(describing: finalElement))"
        menuOperationDiagnostics.record("move.unverified", detail: failureGeometry)
        trace("move unverified \(failureGeometry)")
        throw PlacementError("아이콘 이동 결과를 확인하지 못했어요. 추가 이동은 중단했습니다.")
    }

    static func statusWindowFingerprint() -> Set<String> {
        MenuWindowSnapshot().statusWindowFingerprint()
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
