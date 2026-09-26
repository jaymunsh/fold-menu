import AppKit
import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
private let resources = root.appendingPathComponent("Resources", isDirectory: true)
private let source = resources.appendingPathComponent("AppIcon.svg")

private func color(_ hex: UInt32) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

private func png(width: Int, height: Int, draw: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink,
    ]).draw(at: point)
}

guard let icon = NSImage(contentsOf: source) else {
    fatalError("Unable to load vector source: \(source.path)")
}

let appPNG = png(width: 1024, height: 1024) {
    icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
}
try appPNG.write(to: resources.appendingPathComponent("AppIcon.png"))

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FoldMenuIcon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
for (name, side) in sizes {
    let data = png(width: side, height: side) {
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    }
    try data.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", resources.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }

let preview = png(width: 1200, height: 630) {
    color(0xFFFFFF).setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
    color(0xF3F3F3).setFill()
    NSRect(x: 0, y: 546, width: 1200, height: 84).fill()
    color(0xDEDEDE).setFill()
    NSRect(x: 0, y: 545, width: 1200, height: 1).fill()

    // A quiet menu-bar motif, with the approved A icon as the hero.
    let miniFolder = NSBezierPath(roundedRect: NSRect(x: 58, y: 574, width: 34, height: 24), xRadius: 4, yRadius: 4)
    miniFolder.lineWidth = 2.5
    color(0x242424).setStroke()
    miniFolder.stroke()
    drawText("Fold Menu", at: NSPoint(x: 107, y: 570), size: 25, weight: .semibold, ink: color(0x242424))
    for x: CGFloat in [1066, 1094, 1122] {
        color(0x242424).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 582, width: 8, height: 8)).fill()
    }

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.12)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    icon.draw(in: NSRect(x: 92, y: 98, width: 388, height: 388))
    NSGraphicsContext.restoreGraphicsState()

    drawText("Fold Menu", at: NSPoint(x: 536, y: 353), size: 76, weight: .bold, ink: color(0x242424))
    drawText("메뉴바를 가볍게.", at: NSPoint(x: 540, y: 278), size: 34, weight: .medium, ink: color(0x4A4A4A))
    drawText("숨긴 상태 아이콘을 한 곳에서", at: NSPoint(x: 541, y: 225), size: 24, weight: .regular, ink: color(0x777777))
}
try preview.write(to: resources.appendingPathComponent("GitHubPreview.png"))
print("Generated AppIcon.png, AppIcon.icns, and GitHubPreview.png from AppIcon.svg")
