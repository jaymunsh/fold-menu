import AppKit

/// Routes this app's stamped event through WindowServer and to its window host.
/// Other input is never swallowed.
final class MenuEventDelivery {
    let event: CGEvent
    let pid: pid_t
    let token: Int64
    let relayToPID: Bool
    var received = false
    var mismatch = false

    init(event: CGEvent, pid: pid_t, relayToPID: Bool = true) {
        self.event = event.copy() ?? event
        self.pid = pid
        self.relayToPID = relayToPID
        token = Int64.random(in: 1...Int64(UInt32.max))
        self.event.setIntegerValueField(.eventSourceUserData, value: token)
    }

    @MainActor func send() async throws {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .defaultTap, eventsOfInterest: 1 << event.type.rawValue,
                                         callback: { _, _, incoming, pointer in
            guard let pointer else { return Unmanaged.passUnretained(incoming) }
            let delivery = Unmanaged<MenuEventDelivery>.fromOpaque(pointer).takeUnretainedValue()
            guard incoming.getIntegerValueField(.eventSourceUserData) == delivery.token else {
                return Unmanaged.passUnretained(incoming)
            }
            delivery.received = true
            guard incoming.getIntegerValueField(.mouseEventWindowUnderMousePointer) ==
                    delivery.event.getIntegerValueField(.mouseEventWindowUnderMousePointer) else {
                delivery.mismatch = true
                return nil
            }
            if delivery.relayToPID { delivery.event.postToPid(delivery.pid) }
            return Unmanaged.passUnretained(incoming)
        }, userInfo: context) else {
            throw PlacementError("메뉴바 입력 전달을 시작하지 못했습니다. 손쉬운 사용 권한을 확인해 주세요.")
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        defer {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFMachPortInvalidate(tap)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        trace("tap enabled=\(CGEvent.tapIsEnabled(tap: tap)) event=\(event.type.rawValue) token=\(token)")
        event.post(tap: .cgSessionEventTap)
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(10))
            if received {
                if mismatch { throw PlacementError("macOS가 클릭을 다른 아이콘으로 전달하려 해 중단했습니다.") }
                return
            }
        }
        throw PlacementError("메뉴바 입력 응답을 확인하지 못했습니다.")
    }
}
