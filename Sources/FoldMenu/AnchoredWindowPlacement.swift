import CoreGraphics

enum AnchoredWindowPlacement {
    /// AppKit screen coordinates (y increases upwards). Match the folder panel's
    /// right-edge alignment and keep the whole window inside the usable screen.
    static func origin(size: CGSize, anchor: CGRect, visibleFrame: CGRect) -> CGPoint? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              !anchor.isEmpty, !anchor.isInfinite, !anchor.isNull,
              !visibleFrame.isEmpty, !visibleFrame.isInfinite, !visibleFrame.isNull else { return nil }
        let padding: CGFloat = 8
        let gap: CGFloat = 6
        let minX = visibleFrame.minX + padding
        let maxX = max(minX, visibleFrame.maxX - padding - size.width)
        let minY = visibleFrame.minY + padding
        let top = min(anchor.minY - gap, visibleFrame.maxY - gap)
        return CGPoint(x: min(max(anchor.maxX - size.width, minX), maxX),
                       y: max(top - size.height, minY))
    }
}
