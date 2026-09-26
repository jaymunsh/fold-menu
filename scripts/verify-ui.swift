import AppKit
import ApplicationServices

// Developer UI probe: only reads/presses Fold Menu's accessibility controls.
func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.leneu.foldmenu" }) else {
    fatalError("Fold Menu is not running")
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 1)
let physical = CommandLine.arguments.contains("--physical")
let requested = CommandLine.arguments.dropFirst().first(where: { $0 != "--physical" })
var pressed = false
func visit(_ element: AXUIElement, depth: Int) {
    guard depth < 15 else { return }
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    let title = attr(element, kAXTitleAttribute) as? String ?? ""
    let label = attr(element, kAXDescriptionAttribute) as? String ?? ""
    let value = attr(element, kAXValueAttribute) as? String ?? ""
    print(String(repeating: " ", count: depth), role, title, label, value)
    if !pressed, role == kAXButtonRole, let requested, requested == title || requested == label {
        if physical, let p = attr(element, kAXPositionAttribute), let s = attr(element, kAXSizeAttribute) {
            var point = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &point)
            AXValueGetValue(s as! AXValue, .cgSize, &size)
            point.x += size.width / 2; point.y += size.height / 2
            let cursor = CGEvent(source: nil)?.location
            CGWarpMouseCursorPosition(point)
            Thread.sleep(forTimeInterval: 0.03)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: 1)
                event?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.08)
            }
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            print("PHYSICAL click", point, "(verify post-state separately)")
        } else {
            print("PRESS", AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)
        }
        pressed = true
        return
    }
    for child in attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
}
for window in attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] { visit(window, depth: 0) }
if requested != nil && !pressed { exit(2) }
