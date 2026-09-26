import AppKit
import ApplicationServices

if CommandLine.arguments.contains("--windows") {
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    for entry in windows where entry[kCGWindowLayer as String] as? Int == 25 {
        guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.minY == 0 else { continue }
        print("window", entry[kCGWindowNumber as String] ?? "?", "onscreen", entry[kCGWindowIsOnscreen as String] ?? "?", frame)
    }
    exit(0)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
let targets = ["dev.leneu.foldmenu", "com.electron.dockerdesktop", "app.omlx", "com.stablyai.orca", "io.tailscale.ipn.macos", "io.tailscale.ipn.macsys"]
for app in NSWorkspace.shared.runningApplications where targets.contains(app.bundleIdentifier ?? "") || ["HoldImg", "donts3p", "Stats"].contains(app.localizedName ?? "") {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.5)
    guard let bar = attribute(root, kAXExtrasMenuBarAttribute) else { continue }
    for element in attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        let description = attribute(element, kAXDescriptionAttribute) as? String ?? ""
        if CommandLine.arguments.contains("--open-folder"), app.bundleIdentifier == "dev.leneu.foldmenu", description == "Fold Menu" {
            print("Folder AXPress:", AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)
        }
        var position = CGPoint.zero
        if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgPoint, &position)
        }
        var size = CGSize.zero
        if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        print("\(app.localizedName ?? "") / \(description): x=\(position.x), y=\(position.y), size=\(size)")
    }
}
