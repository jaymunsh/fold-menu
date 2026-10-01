import Foundation

enum MenuOperationDiagnosticsTests {
    static func run() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fold-menu-diagnostics-test-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("nested/last-menu-failure.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        var clock = 100.0
        let diagnostics = MenuOperationDiagnostics(capacity: 3, now: { clock })
        let failure = NSError(domain: "Fixture", code: 73,
                              userInfo: [NSLocalizedDescriptionKey: "PRIVATE_AX_MENU_LABEL"])
        diagnostics.begin(itemID: "docker:0")
        for step in 1...4 {
            clock = 100 + Double(step)
            diagnostics.record("step\(step)", detail: "frame=\(step)")
        }
        clock = 105
        try! diagnostics.saveFailure(failure, to: file)
        let original = try! Data(contentsOf: file)
        let report = try! JSONSerialization.jsonObject(with: original) as! [String: Any]
        let events = report["events"] as! [[String: Any]]
        precondition(report["itemID"] as? String == "docker:0")
        precondition(events.compactMap { $0["stage"] as? String } == ["step3", "step4", "failure"], "Keep only recent operation stages; do not grow a history forever")
        precondition(events.compactMap { $0["elapsed"] as? Double } == [3, 4, 5], "Persist monotonic elapsed time, not just messages")
        precondition(events.last?["detail"] as? String == "operationFailed")
        precondition(!String(decoding: original, as: UTF8.self).contains("PRIVATE_AX_MENU_LABEL"), "AX-derived error descriptions must not be persisted")
        diagnostics.record("late event")
        try! diagnostics.saveFailure(failure, to: file)
        precondition(try! Data(contentsOf: file) == original, "A saved failure closes the operation")

        diagnostics.begin(itemID: "tailscale:0")
        diagnostics.record("opened")
        diagnostics.finish()
        try! diagnostics.saveFailure(failure, to: file)
        precondition(try! Data(contentsOf: file) == original, "Success must not overwrite the last failure or write a new file")

        diagnostics.begin(itemID: String(repeating: "한", count: 1_000))
        diagnostics.record("large", detail: String(repeating: "한", count: 10_000))
        try! diagnostics.saveFailure(failure, to: file)
        let bounded = try! Data(contentsOf: file)
        let boundedReport = try! JSONSerialization.jsonObject(with: bounded) as! [String: Any]
        precondition(boundedReport["itemID"] as? String != "docker:0", "The one file is replaced with the current failure")
        precondition(bounded.count < 10_000, "Large Unicode payloads must remain byte-bounded")
        precondition((try! FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) == ["last-menu-failure.json"])

        diagnostics.begin(itemID: "blocked:0")
        do {
            try diagnostics.saveFailure(failure, to: file.appendingPathComponent("child.json"))
            preconditionFailure("Writing below a regular file must report an I/O failure")
        } catch { /* The app must be able to ignore this without losing recovery. */ }
        diagnostics.begin(itemID: "/Users/PRIVATE_PATH/App.app:0")
        try! diagnostics.saveFailure(CancellationError(), to: file)
        let recovered = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        precondition(recovered["itemID"] as? String == "unidentified-item")
        precondition(!String(decoding: try! Data(contentsOf: file), as: UTF8.self).contains("PRIVATE_PATH"))
        precondition((recovered["events"] as! [[String: Any]]).last?["detail"] as? String == "cancelled")
        print("PASS: bounded operation diagnostics persist only failures, overwrite one file, and recover after I/O errors")
    }
}
