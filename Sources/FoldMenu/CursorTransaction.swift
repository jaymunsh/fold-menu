import AppKit

/// Protects the cursor during a short synthetic input and hosted-layout update.
/// The user's native menu session always runs after finish(), with a normal cursor.
@MainActor
final class CursorTransaction {
    private static weak var active: CursorTransaction?
    private var motion: CursorMotion
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: DispatchWorkItem?
    private var hidden = false
    private var disassociated = false
    private var finished = false
    private let started = ProcessInfo.processInfo.systemUptime

    init() throws {
        guard Self.active == nil, let origin = CGEvent(source: nil)?.location else {
            throw PlacementError("이전 마우스 입력이 끝나지 않았습니다. 잠시 후 다시 눌러 주세요.")
        }
        motion = CursorMotion(desired: origin)
        let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // Observe at HID input, before WindowServer produces tracking movement
        // for our synthetic session clicks. Those generated moves are not user motion.
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                               options: .listenOnly, eventsOfInterest: mask,
                               callback: { _, _, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<CursorTransaction>.fromOpaque(pointer).takeUnretainedValue()
                // Hardware movement has no app stamp. Ignore our own posted events
                // and warps; observe without swallowing or modifying any user input.
                if event.getIntegerValueField(.eventSourceUserData) == 0,
                   event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) {
                    // Position-derived mouseEventDelta can include a cursor
                    // warp on the next hardware event. Raw device movement
                    // excludes that jump, including while the user is moving.
                    let dx = event.getDoubleValueField(.eventUnacceleratedPointerMovementX)
                    let dy = event.getDoubleValueField(.eventUnacceleratedPointerMovementY)
                    owner.motion.record(deltaX: dx, deltaY: dy)
                    if dx != 0 || dy != 0 { trace("cursor physical delta=(\(dx),\(dy))") }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { throw PlacementError("포인터 위치를 보호할 수 없어 입력을 중단했습니다.") }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
        guard hidden else {
            removeMonitor()
            throw PlacementError("포인터 이동을 감출 수 없어 입력을 중단했습니다.")
        }
        // Avoid competing with hardware cursor movement during the short
        // transaction. Raw movement above is applied at restoration instead.
        disassociated = CGAssociateMouseAndMouseCursorPosition(0) == .success
        guard disassociated else {
            removeMonitor()
            CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
            throw PlacementError("포인터 위치를 보호할 수 없어 입력을 중단했습니다.")
        }
        Self.active = self
        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        watchdog = timeout
        // Longer than the bounded input + layout deadline (3.4 seconds).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)
        trace("cursor begin origin=\(origin)")
    }

    func warp(to point: CGPoint) {
        guard !finished, activeDisplayBounds().contains(where: { $0.contains(point) }) else { return }
        CGWarpMouseCursorPosition(point)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        watchdog?.cancel()
        watchdog = nil
        let destination = motion.destination(displays: activeDisplayBounds())
        removeMonitor()
        if let destination { CGWarpMouseCursorPosition(destination) }
        if disassociated { CGAssociateMouseAndMouseCursorPosition(1); disassociated = false }
        if hidden { CGDisplayShowCursor(CGMainDisplayID()); hidden = false }
        Self.active = nil
        trace("cursor restored=\(String(describing: destination)) elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
    }

    static func finishActive() { active?.finish() }

    private func removeMonitor() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }
}
