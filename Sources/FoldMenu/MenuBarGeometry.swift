import CoreGraphics

enum MenuBarGeometry {
    /// Both rectangles must be actual WindowServer status-host bounds, not AX
    /// glyph bounds (which can extend 1pt past the host or have different insets).
    static func isImmediatelyRight(_ candidate: CGRect, of boundary: CGRect) -> Bool {
        !candidate.isEmpty && !boundary.isEmpty
            && candidate.width < 1000 && candidate.height <= 50
            && abs(candidate.minX - boundary.maxX) <= 1
            && abs(candidate.minY - boundary.minY) <= 1
            && abs(candidate.height - boundary.height) <= 1
    }

    static func isInMenuBarLane(_ frame: CGRect, displays: [CGRect]) -> Bool {
        displays.contains { display in
            frame.minY >= display.minY - 3
                && frame.maxY <= display.minY + 48
                && frame.height <= 44
        }
    }

    static func contains(_ frame: CGRect, displays: [CGRect]) -> Bool {
        isInMenuBarLane(frame, displays: displays) && displays.contains { display in
            frame.midX >= display.minX && frame.midX <= display.maxX
        }
    }

    static func isParkedOffscreen(_ frame: CGRect, displays: [CGRect]) -> Bool {
        !frame.isEmpty && !frame.isInfinite && !frame.isNull
            && isInMenuBarLane(frame, displays: displays)
            && !displays.contains { $0.intersects(frame) }
    }
}
