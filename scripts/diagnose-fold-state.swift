import AppKit
import ApplicationServices
import CoreGraphics

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(),
          let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: origin, size: dimensions)
}

func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
    outer.intersects(inner) && !inner.isEmpty
}

let bundleID = "dev.leneu.foldmenu"
let selected = Set(CFPreferencesCopyAppValue("folderIDs.v2" as CFString, bundleID as CFString) as? [String] ?? [])
let returnData = CFPreferencesCopyAppValue("temporaryPlacements.v1" as CFString, bundleID as CFString) as? Data
let returnRecords = returnData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
let screens: [(id: UInt32, frame: CGRect, quartz: CGRect)] = NSScreen.screens.compactMap { screen in
    guard let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
    let id = value.uint32Value
    return (id, screen.frame, CGDisplayBounds(CGDirectDisplayID(id)))
}
let bounds = screens.map(\.quartz)
func isParked(_ rect: CGRect) -> Bool {
    !rect.isEmpty && !bounds.contains(where: { contains($0, rect) })
}

print("macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) displays=\(screens.map { (id: $0.id, frame: $0.frame, quartz: $0.quartz) })")
print("selectedCount=\(selected.count) borrowed=\(returnRecords)")
if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.5)
    let ownItems = attribute(root, kAXExtrasMenuBarAttribute).flatMap {
        attribute($0 as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
    } ?? []
    for (index, item) in ownItems.enumerated() {
        let label = (attribute(item, kAXDescriptionAttribute) as? String)
            ?? (attribute(item, kAXTitleAttribute) as? String) ?? ""
        if label.contains("Fold Menu") {
            let value = attribute(item, kAXValueAttribute).map { String(describing: $0) } ?? "nil"
            print("folderStatusItem index=\(index) label=\(label) value=\(value) frame=\(String(describing: frame(item)))")
        }
    }
    for id in selected.sorted() {
        guard let separator = id.lastIndex(of: ":"),
              let index = Int(id[id.index(after: separator)...]),
              let owner = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == String(id[..<separator])
              }) else {
            print("selected \(id): owner unavailable")
            continue
        }
        let ownerRoot = AXUIElementCreateApplication(owner.processIdentifier)
        AXUIElementSetMessagingTimeout(ownerRoot, 0.5)
        let items = attribute(ownerRoot, kAXExtrasMenuBarAttribute).flatMap {
            attribute($0 as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
        } ?? []
        guard items.indices.contains(index), let rect = frame(items[index]) else {
            print("selected \(id): AX item unavailable")
            continue
        }
        print("selected \(id) name=\(owner.localizedName ?? "?") frame=\(rect) parked=\(isParked(rect))")
    }
}

let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windowInfo where window[kCGWindowLayer as String] as? Int == 25 {
    guard let number = window[kCGWindowNumber as String] as? NSNumber,
          let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
          let owner = window[kCGWindowOwnerName as String] as? String,
          let dictionary = window[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
          rect.width > 1000 || pid.int32Value == NSRunningApplication.current.processIdentifier else { continue }
    print("statusHost window=\(number.uint32Value) owner=\(owner) pid=\(pid.int32Value) onscreen=\(window[kCGWindowIsOnscreen as String] ?? "?") frame=\(rect)")
}
