import CoreGraphics

/// Tracks user movement independently of synthetic menu-bar coordinates.
struct CursorMotion {
    private(set) var desired: CGPoint

    mutating func record(deltaX: Double, deltaY: Double) {
        guard deltaX.isFinite, deltaY.isFinite else { return }
        desired.x += deltaX
        desired.y += deltaY
    }

    func destination(displays: [CGRect]) -> CGPoint? {
        let valid = displays.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        if valid.contains(where: { $0.contains(desired) }) { return desired }
        // Display removal/gaps must not turn a restore into another offscreen warp.
        return valid.map {
            CGPoint(x: min(max(desired.x, $0.minX), $0.maxX - 1),
                    y: min(max(desired.y, $0.minY), $0.maxY - 1))
        }.min {
            hypot($0.x - desired.x, $0.y - desired.y) < hypot($1.x - desired.x, $1.y - desired.y)
        }
    }
}
