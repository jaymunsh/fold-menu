import CoreGraphics

enum AnchoredWindowPlacementTests {
    static func run() {
        let screen = CGRect(x: 0, y: 40, width: 1800, height: 1090)
        let anchor = CGRect(x: 1212, y: 1130, width: 38, height: 39)
        let size = CGSize(width: 380, height: 205)
        let point = AnchoredWindowPlacement.origin(size: size, anchor: anchor, visibleFrame: screen)!
        precondition(point == CGPoint(x: 870, y: 919), "Settings must sit six points below the folder")
        let taller = AnchoredWindowPlacement.origin(size: CGSize(width: 380, height: 280), anchor: anchor, visibleFrame: screen)!
        precondition(taller.y + 280 == point.y + 205, "Messages must grow downwards from the same anchor")
        let left = AnchoredWindowPlacement.origin(size: size, anchor: CGRect(x: 0, y: 1130, width: 38, height: 39), visibleFrame: screen)!
        precondition(left.x == 8)
        let right = AnchoredWindowPlacement.origin(size: size, anchor: CGRect(x: 1780, y: 1130, width: 20, height: 39), visibleFrame: screen)!
        precondition(right.x + size.width == 1792)
        let otherScreen = CGRect(x: -1440, y: -860, width: 1440, height: 860)
        let other = AnchoredWindowPlacement.origin(size: size, anchor: CGRect(x: -500, y: 0, width: 38, height: 24), visibleFrame: otherScreen)!
        precondition(other == CGPoint(x: -842, y: -211), "Use the anchor display, including negative screen coordinates")
        precondition(AnchoredWindowPlacement.origin(size: .zero, anchor: anchor, visibleFrame: screen) == nil)
        print("PASS: settings anchors below the folder and clamps at screen edges")
    }
}
