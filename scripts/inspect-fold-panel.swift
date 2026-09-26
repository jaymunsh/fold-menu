import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}

func line(_ element: AXUIElement) -> String {
    let role = value(element, kAXRoleAttribute) as? String ?? "?"
    let title = value(element, kAXTitleAttribute) as? String ?? ""
    let label = value(element, kAXDescriptionAttribute) as? String ?? ""
    let contents = value(element, kAXValueAttribute) as? String ?? ""
    return "role=\(role) title=\(title) label=\(label) value=\(contents)"
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.leneu.foldmenu" }) else {
    fatalError("Fold Menu is not running")
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.5)
let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
print("windows=\(windows.count)")
for (index, window) in windows.enumerated() {
    print("window[\(index)] \(line(window))")
    let children = value(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
    for (childIndex, child) in children.enumerated() {
        print("  child[\(childIndex)] \(line(child))")
        let grandchildren = value(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for (grandchildIndex, grandchild) in grandchildren.enumerated() {
            print("    child[\(childIndex)][\(grandchildIndex)] \(line(grandchild))")
        }
    }
}
