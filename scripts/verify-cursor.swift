import AppKit
import ApplicationServices

let original = CGEvent(source: nil)?.location
let measureCursor = !CommandLine.arguments.contains("--geometry-only")
var userMoved = false
func fail(_ message: String) -> Never {
    if measureCursor, !userMoved, let original { CGWarpMouseCursorPosition(original) }
    print("INCOMPLETE: \(message)")
    exit(2)
}
// Distinguish a regression from the user legitimately moving during the test.
let movementTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
    options: .listenOnly, eventsOfInterest: 1 << CGEventType.mouseMoved.rawValue,
    callback: { _, _, event, _ in
        if event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()),
           event.getDoubleValueField(.eventUnacceleratedPointerMovementX) != 0 ||
           event.getDoubleValueField(.eventUnacceleratedPointerMovementY) != 0 {
            userMoved = true
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)
guard let movementTap else { fail("Cannot observe concurrent user input") }
let movementSource = CFMachPortCreateRunLoopSource(nil, movementTap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), movementSource, .commonModes)
CGEvent.tapEnable(tap: movementTap, enable: true)
func pause(_ seconds: Double) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

// Live regression probe. Opens only the requested item's native menu, dismisses
// it with Escape, and measures the pointer after both short input transactions.
let inputs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let itemName = inputs.first ?? "donts3p"
let itemBundle = inputs.dropFirst().first ?? "org.donts3p"
let injectMovement = CommandLine.arguments.contains("--move-during-input")
guard measureCursor || !injectMovement else { fail("--geometry-only cannot inject pointer movement") }
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.leneu.foldmenu" }),
      let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == itemBundle }) else { fail("Required app not running") }
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 1)
func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func button(_ label: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 15 else { return nil }
    if attr(element, kAXRoleAttribute) as? String == kAXButtonRole,
       (attr(element, kAXTitleAttribute) as? String == label || attr(element, kAXDescriptionAttribute) as? String == label) { return element }
    for child in attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = button(label, in: child, depth: depth + 1) { return match }
    }
    return nil
}
func find(_ label: String) -> AXUIElement? {
    for window in attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        if let result = button(label, in: window) { return result }
    }
    return nil
}
func press(_ label: String) {
    guard let element = find(label), AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { fail("Cannot press \(label)") }
}
func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
func sample(for duration: Double, checkingAfter delay: Double, expected: CGPoint) -> (deviation: Double, finalDeviation: Double, physicalMovement: Bool) {
    let start = ProcessInfo.processInfo.systemUptime
    var deviation = 0.0
    var physicalMovement = false
    while ProcessInfo.processInfo.systemUptime - start < duration {
        if ProcessInfo.processInfo.systemUptime - start >= delay, let point = CGEvent(source: nil)?.location {
            deviation = max(deviation, distance(point, expected))
            if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved) < 0.01 { physicalMovement = true }
        }
        pause(0.005)
    }
    return (deviation, distance(CGEvent(source: nil)?.location ?? expected, expected), physicalMovement)
}
defer {
    CFMachPortInvalidate(movementTap)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), movementSource, .commonModes)
    if measureCursor, !userMoved, let original { CGWarpMouseCursorPosition(original) }
}
let openingPoint = measureCursor ? CGPoint(x: 900, y: 500) : original ?? .zero
if measureCursor { CGWarpMouseCursorPosition(openingPoint) }
if find(itemName) == nil {
    press("Fold Menu")
    // AXPress can return before SwiftUI exposes the panel's item buttons.
    // Wait for the requested control rather than assuming a 50ms render.
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while find(itemName) == nil && ProcessInfo.processInfo.systemUptime < deadline {
        pause(0.05)
    }
}
press(itemName)
var expectedOpening = openingPoint
if injectMovement {
    // Move during layout settling, after the synthetic press/release, so this
    // probes preservation without deliberately turning the move into a user drag.
    pause(0.16)
    let current = CGEvent(source: nil)?.location ?? openingPoint
    let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                        mouseCursorPosition: CGPoint(x: current.x + 24, y: current.y + 12), mouseButton: .left)
    event?.setIntegerValueField(.mouseEventDeltaX, value: 24)
    event?.setIntegerValueField(.mouseEventDeltaY, value: 12)
    event?.setDoubleValueField(.eventUnacceleratedPointerMovementX, value: 24)
    event?.setDoubleValueField(.eventUnacceleratedPointerMovementY, value: 12)
    event?.post(tap: .cghidEventTap)
    expectedOpening.x += 24; expectedOpening.y += 12
}
let opening = sample(for: 1.8, checkingAfter: 1.3, expected: expectedOpening)
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? [[String: Any]] ?? []
let menuOpen = windows.contains { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.processIdentifier && $0[kCGWindowLayer as String] as? Int == 101 }
// Independent WindowServer assertion: the actual source host must directly
// abut the live folder spacer, with no skipped visible icon between them.
let allWindows = CGWindowListCopyWindowInfo(.optionAll, 0) as? [[String: Any]] ?? []
let statusFrames = allWindows.compactMap { entry -> CGRect? in
    guard entry[kCGWindowLayer as String] as? Int == 25,
          (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != app.processIdentifier,
          let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
}
var sourceFrame: CGRect?
let targetRoot = AXUIElementCreateApplication(target.processIdentifier)
if let bar = attr(targetRoot, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
   let child = (attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement])?.first,
   let p = attr(child, kAXPositionAttribute), let s = attr(child, kAXSizeAttribute) {
    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    let midpoint = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    sourceFrame = statusFrames.filter { $0.contains(midpoint) && $0.width < 1000 }.min { $0.width < $1.width }
}
let spacers = statusFrames.filter { $0.width > 1000 && $0.height > 0 && $0.height <= 50 }
let gap: CGFloat? = sourceFrame.flatMap { source in
    let adjacentLane = spacers.filter { abs($0.minY - source.minY) <= 1 && $0.maxX <= source.minX + 1 }
    guard adjacentLane.count == 1 else { return nil }
    return source.minX - adjacentLane[0].maxX
}
let adjacent = gap.map { abs($0) <= 1 } ?? false
let closingPoint = userMoved ? (CGEvent(source: nil)?.location ?? openingPoint) : CGPoint(x: 940, y: 530)
if measureCursor { CGWarpMouseCursorPosition(closingPoint) }
for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(target.processIdentifier) }
// The cursor is intentionally hidden while the hosted release is settling.
// Measure after that bounded operation rather than count its hidden coordinates.
let closing = sample(for: 3.5, checkingAfter: 3.0, expected: closingPoint)
CFPreferencesAppSynchronize("dev.leneu.foldmenu" as CFString)
let placementData = CFPreferencesCopyAppValue("temporaryPlacements.v1" as CFString, "dev.leneu.foldmenu" as CFString) as? Data
let placements = placementData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
let pendingReturn = placements.map { $0.keys.contains { $0.hasPrefix(itemBundle + ":") } }
print("item=\(itemName) menuObserved=\(menuOpen) folderGap=\(String(describing: gap)) sourceHost=\(String(describing: sourceFrame)) pendingReturn=\(String(describing: pendingReturn))")
if !measureCursor {
    // No test-generated pointer repositioning; the app's own transport still
    // runs normally. This mode only certifies menu, adjacency and return state.
    exit(menuOpen && adjacent && pendingReturn == false ? 0 : 1)
}
print("injectedMovement=\(injectMovement) opening=\(opening) closing=\(closing)")
if !userMoved, let original { CGWarpMouseCursorPosition(original) }
if userMoved || opening.physicalMovement || closing.physicalMovement { print("INCOMPLETE: user moved the pointer during measurement"); exit(2) }
if !menuOpen || !adjacent || pendingReturn != false || opening.deviation > 1 || closing.deviation > 1 { exit(1) }
