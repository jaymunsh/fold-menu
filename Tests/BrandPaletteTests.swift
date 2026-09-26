import AppKit
import Foundation

for path in CommandLine.arguments.dropFirst() {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let image = NSBitmapImageRep(data: data) else {
        fatalError("Cannot read image: \(path)")
    }

    for y in stride(from: 0, to: image.pixelsHigh, by: 16) {
        for x in stride(from: 0, to: image.pixelsWide, by: 16) {
            guard let sample = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  sample.alphaComponent > 0.95 else { continue }
            let channels = [sample.redComponent, sample.greenComponent, sample.blueComponent]
            if let lowest = channels.min(), let highest = channels.max(), highest - lowest > 0.012 {
                fputs("Non-gray pixel in \(path) at (\(x), \(y)): \(channels)\n", stderr)
                exit(1)
            }
        }
    }
    print("PASS: grayscale palette in \(path)")
}
