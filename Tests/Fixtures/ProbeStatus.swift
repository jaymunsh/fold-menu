import AppKit

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "FoldMenu.TestProbe"
        item.button?.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Fold Probe")
        item.button?.toolTip = "Fold Probe"
        item.button?.setAccessibilityLabel("Fold Probe")
        let menu = NSMenu()
        menu.addItem(withTitle: "Probe action", action: nil, keyEquivalent: "")
        item.menu = menu
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
