import CoreGraphics

enum StatusWindowFingerprint {
    static func key(windowID: UInt32, frame: CGRect) -> String {
        "\(windowID)@\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))"
    }
}
