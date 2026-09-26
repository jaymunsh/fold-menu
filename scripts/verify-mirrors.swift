import AppKit
import ApplicationServices
import CoreGraphics

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &result) else { return nil }
    return result
}

func size(_ element: AXUIElement, _ name: String) -> CGSize? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var result = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
    return result
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.leneu.foldmenu" }) else {
    fatalError("Fold Menu is not running")
}
let displays: [(id: UInt32, frame: CGRect)] = NSScreen.screens.compactMap { screen in
    guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
    return (id, screen.frame)
}
let target = CommandLine.arguments.dropFirst().first.flatMap(UInt32.init)
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 1)

if let target {
    guard let screen = displays.first(where: { $0.id == target }) else { fatalError("No active display \(target)") }
    let quartzScreen = CGDisplayBounds(CGDirectDisplayID(screen.id))
    let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
    var pressed = false
    for window in windows {
        guard let origin = point(window, kAXPositionAttribute),
              let dimensions = size(window, kAXSizeAttribute),
              dimensions.width < 100, dimensions.height < 60,
              quartzScreen.contains(CGPoint(x: origin.x + dimensions.width / 2,
                                            y: origin.y + dimensions.height / 2)) else { continue }
        let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if let button = children.first(where: {
            (attribute($0, kAXRoleAttribute) as? String) == kAXButtonRole
                && (attribute($0, kAXDescriptionAttribute) as? String) == "Fold Menu"
        }) {
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            print("AXPress display=\(target) result=\(result.rawValue)")
            pressed = result == .success
            break
        }
    }
    guard pressed else { fatalError("Fold Menu mirror for display \(target) was not found or could not be pressed") }
    Thread.sleep(forTimeInterval: 0.4)
}

let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
let mirrors = owned.compactMap { entry -> (UInt32, CGRect)? in
    guard entry[kCGWindowLayer as String] as? Int == 25,
          let bounds = entry[kCGWindowBounds as String] as? [String: Any],
          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
          frame.width <= 100, frame.height <= 60,
          let display = displays.first(where: { display in
              let cocoaFrame = CGRect(x: frame.minX,
                                      y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY,
                                      width: frame.width, height: frame.height)
              return display.frame.intersects(cocoaFrame)
          }) else { return nil }
    return (display.id, frame)
}.sorted { $0.0 < $1.0 }
let statusExtras = attribute(root, kAXExtrasMenuBarAttribute).flatMap {
    attribute($0 as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
}?.count ?? -1
print("pid=\(app.processIdentifier) screens=\(displays.map(\.id)) nativeStatusItems=\(statusExtras) mirrors=\(mirrors)")

let visibleOwned = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
let visiblePanel = visibleOwned.first { ($0[kCGWindowName as String] as? String) == "Fold Menu Folder" }
if visiblePanel == nil { print("folderPanel=hidden") }
for entry in visibleOwned where (entry[kCGWindowName as String] as? String) == "Fold Menu Folder" {
    guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
          let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
    let quartzCenter = CGPoint(x: frame.midX, y: frame.midY)
    let display = displays.first { item in
        let quartzFrame = CGRect(x: item.frame.minX,
                                 y: (NSScreen.screens.first?.frame.maxY ?? 0) - item.frame.maxY,
                                 width: item.frame.width, height: item.frame.height)
        return quartzFrame.contains(quartzCenter)
    }
    print("folderPanel=visible display=\(display?.id.description ?? "none") frame=\(frame)")
}
