import AppKit
import ApplicationServices

// Live regression check: only Fold Menu's own edit/finish controls are pressed.
// Never drags or activates another application's status item.
func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func selectedIDs() -> Set<String> {
    CFPreferencesAppSynchronize("dev.leneu.foldmenu" as CFString)
    return Set(CFPreferencesCopyAppValue("folderIDs.v2" as CFString, "dev.leneu.foldmenu" as CFString) as? [String] ?? [])
}
let selected = selectedIDs()
guard !selected.isEmpty, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.leneu.foldmenu" }) else {
    fail("Open Fold Menu settings with an existing nonempty folder first")
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.5)
func find(_ label: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 15 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXDescriptionAttribute) as? String == label || attribute(element, kAXTitleAttribute) as? String == label { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let result = find(label, in: child, depth: depth + 1) { return result }
    }
    return nil
}
func button(_ label: String) -> AXUIElement? {
    for window in attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        if let result = find(label, in: window) { return result }
    }
    return nil
}
func press(_ label: String) {
    guard let button = button(label), AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
        fail("Could not press \(label)")
    }
}
func waitUntil(_ condition: () -> Bool) -> Bool {
    let limit = Date().addingTimeInterval(12)
    repeat {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    } while Date() < limit
    return false
}
func selectedFrames() -> [String: CGRect] {
    var result: [String: CGRect] = [:]
    for id in selected {
        guard let separator = id.lastIndex(of: ":"), let index = Int(id[id.index(after: separator)...]),
              let owner = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == String(id[..<separator]) }) else { continue }
        let application = AXUIElementCreateApplication(owner.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let bar = attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement], children.indices.contains(index),
              let position = attribute(children[index], kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(children[index], kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        result[id] = CGRect(origin: p, size: s)
    }
    return result
}
let primaryTop = NSScreen.screens.first!.frame.maxY
let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
func hidden() -> Bool {
    let frames = selectedFrames()
    return frames.count == selected.count && frames.values.allSatisfy { frame in
        !frame.isEmpty && !screens.contains { $0.intersects(frame) }
    } && button("Fold Menu") != nil
}

guard waitUntil(hidden) else { fail("Initial folder is not hidden: \(selectedFrames())") }
print("PASS: initial \(selected.count) items are offscreen, folder button available")
for round in 1...3 {
    press("항목 편집 시작")
    guard waitUntil({
        let frames = selectedFrames()
        return button("편집 완료하고 접기") != nil && frames.count == selected.count
            && frames.values.allSatisfy { frame in screens.contains { $0.intersects(frame) } }
    }) else {
        fail("Round \(round): editing did not expose the original items")
    }
    press("편집 완료하고 접기")
    guard waitUntil(hidden) else { fail("Round \(round): collapse failed: \(selectedFrames())") }
    guard selectedIDs() == selected else { fail("Round \(round): selected IDs changed; stopping") }
    print("PASS: edit/collapse round \(round), same \(selected.count) selections")
}
for round in 1...3 {
    press("완료")
    press("Fold Menu")
    guard waitUntil({ button("설정") != nil }) else { fail("Folder panel did not remain open; check concurrent user input") }
    press("설정")
    guard waitUntil({ button("항목 편집 시작") != nil && hidden() }) else { fail("Settings reopen unfolded the folder") }
    print("PASS: folder/settings reopen round \(round)")
}
let until = Date().addingTimeInterval(60)
var samples = 0
while Date() < until {
    guard hidden() else { fail("Folder unexpectedly expanded: \(selectedFrames())") }
    samples += 1
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
}
print("PASS: hidden for 60 seconds across \(samples) independent AX samples")
print("Final frames: \(selectedFrames())")
