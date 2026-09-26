import CoreGraphics

enum CursorMotionTests {
    static func run() {
        let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        var motion = CursorMotion(desired: CGPoint(x: 900, y: 450))
        precondition(motion.destination(displays: [display]) == CGPoint(x: 900, y: 450))
        motion.record(deltaX: 30, deltaY: -12)
        precondition(motion.destination(displays: [display]) == CGPoint(x: 930, y: 438), "User movement must not be undone by a stale restore")
        motion.record(deltaX: .nan, deltaY: 10)
        precondition(motion.desired == CGPoint(x: 930, y: 438))
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let onLeft = CursorMotion(desired: CGPoint(x: -100, y: 400))
        precondition(onLeft.destination(displays: [left, display]) == CGPoint(x: -100, y: 400), "Negative coordinates are valid on a left-hand display")
        precondition(onLeft.destination(displays: [display]) == CGPoint(x: 0, y: 400), "Removed displays must be clamped safely")
        precondition(onLeft.destination(displays: []) == nil)
        print("PASS: cursor restoration preserves physical movement and display bounds")
    }
}
