@main
enum SelectionTests {
    static func main() {
        precondition(Selection.updating(excluded: ["docker"], id: "docker", enabled: true) == [], "Enabling includes the item")
        precondition(Selection.updating(excluded: [], id: "docker", enabled: false) == ["docker"], "Disabling excludes the item")
        let first = Selection.updating(excluded: [], id: "docker", enabled: false)
        precondition(Selection.updating(excluded: first, id: "docker", enabled: false) == first, "Selection updates are idempotent")
        print("PASS: enable, disable, repeated selection")
        MenuBarGeometryTests.run()
        MenuBarMirrorPlacementTests.run()
        MenuSessionTests.run()
        CursorMotionTests.run()
        FolderIndicatorTests.run()
        NativeMenuPressTests.run()
        MenuPlacementSettlingTests.run()
        StatusWindowFingerprintTests.run()
        MenuWindowSnapshotTests.run()
        MenuIconIndexTests.run()
        MenuOperationDiagnosticsTests.run()
        DiscoveryScanPolicyTests.run()
        AnchoredWindowPlacementTests.run()
        FolderAnchorTrackingTests.run()
        FoldRecoveryTests.run()
    }
}
