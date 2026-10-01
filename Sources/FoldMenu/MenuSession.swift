import AppKit
import ApplicationServices

enum MenuSession {
    static func windows(for pids: Set<pid_t>) -> Set<CGWindowID> {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? NSNumber, pids.contains(pid.int32Value),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  MenuSessionPolicy.isPopupLayer(layer),
                  let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            return number.uint32Value
        })
    }

    @MainActor static func pressAndWait(_ item: MenuItem, onOpen: () -> Void) async throws {
        // move() has already verified settled geometry. No extra pause or
        // second pointer trip is needed when the item supports native AXPress.
        var ownerPID: pid_t = 0
        AXUIElementGetPid(item.element, &ownerPID)
        guard let rect = menuElementFrame(item.element),
              let host = MenuTransport.host(at: CGPoint(x: rect.midX, y: rect.midY)), host.visible else {
            throw PlacementError("메뉴를 열 아이콘이 아직 화면에 보이지 않아요.")
        }
        let owners: Set<pid_t> = [ownerPID, host.pid]
        let baseline = windows(for: owners)
        let wasFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID
        try Task.checkCancellation()
        switch NativeMenuPress.press(item.element) {
        case .requested:
            menuOperationDiagnostics.record("menu.press", detail: "AXPress requested")
            trace("native press requested \(item.id)")
        case .unsupported:
            menuOperationDiagnostics.record("menu.press", detail: "AXPress unsupported; pointer fallback")
            trace("native press unsupported; pointer fallback \(item.id)")
            try await MenuTransport.click(at: CGPoint(x: rect.midX, y: rect.midY), host: host)
        case .failed(let error):
            menuOperationDiagnostics.record("menu.pressFailed", detail: "AXError=\(error.rawValue)")
            throw PlacementError("\(item.name)의 메뉴 열기 요청에 실패했습니다 (\(error.rawValue)).")
        }
        var tracker = MenuSessionPolicy()
        for attempt in 0..<225 {
            try await Task.sleep(for: .milliseconds(200))
            let menus = windows(for: owners).subtracting(baseline)
            let firstOpen = !tracker.appeared && !menus.isEmpty
            if tracker.observe(hasPopup: !menus.isEmpty) {
                menuOperationDiagnostics.record("menu.dismissed")
                trace("menu dismissed \(item.id)"); return
            }
            if firstOpen {
                menuOperationDiagnostics.record("menu.opened", detail: "windows=\(menus)")
                trace("menu observed \(item.id) windows=\(menus)"); onOpen()
            }
            if !tracker.appeared && attempt >= 4 && !wasFrontmost,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID {
                trace("application activated \(item.id)")
                return
            }
            if !tracker.appeared && attempt >= 14 {
                throw PlacementError("\(item.name)의 메뉴가 열리지 않았습니다.")
            }
        }
        throw PlacementError("메뉴 대기를 종료했습니다. 메뉴를 닫고 폴더에서 다시 눌러 주세요.")
    }
}
