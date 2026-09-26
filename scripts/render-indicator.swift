import AppKit

@main
enum RenderIndicator {
    static func main() throws {
        _ = NSApplication.shared
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 144,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = NSAffineTransform()
        scale.scale(by: 2)
        scale.concat()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 360, height: 72).fill()
        for (index, count) in [0, 1, 4, 12, 99, 100].enumerated() {
            let x = CGFloat(index) * 56 + 15
            FolderIndicator.image(count: count).draw(in: NSRect(x: x, y: 34, width: 26, height: 20))
            let label = NSAttributedString(string: String(count), attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.gray
            ])
            label.draw(at: NSPoint(x: x, y: 10))
        }
        NSGraphicsContext.restoreGraphicsState()
        let path = CommandLine.arguments.dropFirst().first ?? ".build/checks/folder-indicator.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print(path)
    }
}
