import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import Combine

func trace(_ message: String) {
    guard CommandLine.arguments.contains("--trace") else { return }
    FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func isInMenuBarStrip(_ frame: CGRect) -> Bool {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return MenuBarGeometry.contains(frame, displays: ids.map(CGDisplayBounds))
}

func activeDisplayBounds() -> [CGRect] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.map(CGDisplayBounds)
}

func capturedStatusIcon(at point: CGPoint) -> NSImage? {
    guard let host = MenuTransport.host(at: point), host.visible,
          let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, host.window,
                                                [.boundsIgnoreFraming, .bestResolution]) else { return nil }
    let image = NSImage(cgImage: cgImage, size: host.frame.size)
    // Menu-bar glyphs are normally monochrome. Mark the captured glyph as a
    // template so it follows the folder panel's light/dark foreground color.
    image.isTemplate = true
    return image
}

struct MenuItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let element: AXUIElement
    let frame: CGRect
}

final class StatusOverlayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FolderOverlay {
    let displayID: UInt32
    let panel: NSPanel
    let button: StatusOverlayButton

    init(displayID: UInt32, panel: NSPanel, button: StatusOverlayButton) {
        self.displayID = displayID
        self.panel = panel
        self.button = button
    }
}

@MainActor
final class MenuStore: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var trusted = AXIsProcessTrusted()
    @Published var message = ""
    @Published var scanning = false
    @Published var arranging = false
    @Published var activity = ""
    @Published var borrowedCount = 0
    @Published var layoutEditing = false
    @Published var collapsed = false
    @Published var folderIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "folderIDs.v2") ?? [])
    private var refreshWaiters: [() -> Void] = []
    private var scanApplications: [NSRunningApplication] = []
    private var scanResults: [MenuItem] = []
    var selected: [MenuItem] {
        items.filter { folderIDs.contains($0.id) }.sorted { $0.frame.minX < $1.frame.minX }
    }

    func captureFolderItems(leftOf folderX: CGFloat) {
        let visible = items.filter { isInMenuBarStrip($0.frame) }
        folderIDs = Set(visible.filter { $0.frame.midX < folderX }.map(\.id))
        UserDefaults.standard.set(Array(folderIDs), forKey: "folderIDs.v2")
        UserDefaults.standard.set(true, forKey: "layout.v2.completed")
        UserDefaults.standard.synchronize()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        trusted = AXIsProcessTrusted()
        if let completion { refreshWaiters.append(completion) }
        guard trusted, !arranging else {
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0() }
            return
        }
        // A scan can take several seconds because some apps answer AX slowly.
        // Never finish editing against stale results while that scan is running.
        guard !scanning else { return }
        scanning = true
        let systemOwners: Set<String> = [
            "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.TextInputMenuAgent",
            "com.apple.TextInputSwitcher", "com.apple.menuextra.clock", "com.apple.Spotlight"
        ]
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && !systemOwners.contains($0.bundleIdentifier ?? "")
                && !($0.bundleURL?.path.hasPrefix("/System/Library/Input Methods/") ?? false)
        }
        scanApplications = applications
        scanResults = []
        scanNextApplication(at: 0)
    }

    private func scanNextApplication(at index: Int) {
        guard index < scanApplications.count else {
            items = scanResults.sorted { $0.frame.minX < $1.frame.minX }
            scanApplications = []
            scanResults = []
            scanning = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0() }
            return
        }

        let app = scanApplications[index]
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        if let value = attribute(root, kAXExtrasMenuBarAttribute),
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            let children = attribute(value as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for (childIndex, child) in children.enumerated() {
                guard let frame = menuElementFrame(child),
                      MenuBarGeometry.isInMenuBarLane(frame, displays: activeDisplayBounds()) else { continue }
                let owner = app.bundleIdentifier ?? app.executableURL?.path ?? String(app.processIdentifier)
                let id = "\(owner):\(childIndex)"
                let title = (attribute(child, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (attribute(child, kAXDescriptionAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? app.localizedName ?? "Menu item"
                let icon = items.first(where: { $0.id == id })?.icon
                    ?? capturedStatusIcon(at: CGPoint(x: frame.midX, y: frame.midY))
                    ?? app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
                scanResults.append(MenuItem(id: id, name: title, icon: icon, element: child, frame: frame))
            }
        }
        // AX menu extras are reliable on the main thread on macOS 26. Yield
        // between applications so a slow app cannot freeze the settings UI.
        DispatchQueue.main.async { [weak self] in self?.scanNextApplication(at: index + 1) }
    }

    func syncNewParkedItems() {
        guard collapsed else { return }
        let displays = activeDisplayBounds()
        let parked = Set(items.filter {
            MenuBarGeometry.isParkedOffscreen($0.frame, displays: displays)
        }.map(\.id))
        let added = parked.subtracting(folderIDs)
        guard !added.isEmpty else { return }
        folderIDs.formUnion(added)
        UserDefaults.standard.set(Array(folderIDs), forKey: "folderIDs.v2")
        UserDefaults.standard.synchronize()
        message = "새 메뉴바 항목 \(added.count)개를 폴더에 추가했습니다."
    }
}

struct FolderView: View {
    @ObservedObject var store: MenuStore
    var settings: () -> Void
    var activate: (MenuItem) -> Void
    var cancel: () -> Void
    var restore: () -> Void
    var refold: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fold Menu", systemImage: "folder").font(.headline)
                Text("\(store.selected.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(action: settings) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help("설정").accessibilityLabel("설정")
            }
            if !store.trusted {
                Text("실제 메뉴바 항목을 열려면 손쉬운 사용 권한이 필요합니다.").foregroundStyle(.secondary)
                Button("손쉬운 사용 허용") { store.requestAccessibility() }
            } else if store.selected.isEmpty {
                Text("폴더가 비어 있습니다. 설정에서 항목 편집을 시작하세요.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.selected) { item in
                            Button { activate(item) } label: {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .renderingMode(item.icon.isTemplate ? .template : .original)
                                    .foregroundStyle(.primary)
                                    .scaledToFit()
                                    .frame(width: 24, height: 24).frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain).help(item.name).accessibilityLabel(item.name)
                            .disabled(store.arranging)
                        }
                    }.padding(2)
                }.frame(height: 44)
            }
            if !store.message.isEmpty {
                Text(store.message).font(.caption).foregroundStyle(.orange)
            }
            if !store.collapsed && !store.layoutEditing && !store.arranging && !store.selected.isEmpty {
                Button("다시 접기", action: refold)
            }
            if store.arranging {
                HStack {
                    Text(store.activity).font(.caption)
                    Spacer()
                    Button("대기 취소", action: cancel)
                }
            } else if store.borrowedCount > 0 {
                Button("꺼낸 항목 되돌리기", action: restore)
            }
        }.padding(16).frame(width: 360)
    }
}

struct SettingsView: View {
    @ObservedObject var store: MenuStore
    var beginEditing: () -> Void
    var finishEditing: () -> Void
    var close: () -> Void
    var cancel: () -> Void
    var refold: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fold Menu 설정").font(.headline)
                Spacer()
                Text("\(store.selected.count)개").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GroupBox("폴더 항목 편집") {
                VStack(alignment: .leading, spacing: 10) {
                    if store.layoutEditing {
                        Text("⌘ 키를 누른 채 메뉴바 안에서 좌우로만 옮기세요.\n폴더 왼쪽은 폴더 안, 오른쪽은 항상 표시입니다.")
                        Text("메뉴바 아래로 놓으면 macOS가 항목을 제거합니다.")
                            .foregroundStyle(.red).font(.caption)
                        Button("편집 완료하고 접기", action: finishEditing)
                    } else {
                        Text("아이콘을 넣거나 뺄 때만 숨긴 항목을 펼칩니다.")
                        Button("항목 편집 시작", action: beginEditing)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !store.trusted { Button("손쉬운 사용 허용") { store.requestAccessibility() } }
            if !CGPreflightScreenCaptureAccess() {
                Button("화면 기록 허용 — 실제 상태 아이콘 표시") { store.requestScreenRecording() }
            }
            if store.arranging {
                HStack { Text(store.activity).font(.caption); Button("대기 취소", action: cancel) }
            }
            if !store.message.isEmpty { Text(store.message).foregroundStyle(.orange).font(.caption) }
            if !store.collapsed && !store.layoutEditing && !store.arranging && !store.selected.isEmpty {
                Button("다시 접기", action: refold)
            }
            HStack {
                Button("메뉴바 설정 열기") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                Button("완료", action: close)
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let collapsedLength: CGFloat = 10_000
    let store = MenuStore()
    var folder: NSStatusItem!
    private var folderOverlays: [UInt32: FolderOverlay] = [:]
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    var outsideMonitor: Any?
    var settingsWindow: NSWindow?
    private var settingsFollowsFolder = false
    private var settingsNeedsPresentation = false
    private var positioningSettings = false
    var menuTask: Task<Void, Never>?
    var startupTask: Task<Void, Never>?
    var expandedFolderFrame: NSRect?
    private var lastFolderAnchor: (displayID: UInt32, frame: NSRect)?
    var discoveryTimer: Timer?
    private var discoveryScanPolicy = DiscoveryScanPolicy()
    var anchorTimer: Timer?
    private var anchorTracking = FolderAnchorTracking()
    private var workspaceWakeObservers: [NSObjectProtocol] = []
    private var applicationScreenObserver: NSObjectProtocol?
    private var wakeRecoveryTask: Task<Void, Never>?
    private var wakeRecoveryRequested = false
    private var wakeRecoveryInProgress = false
    private var wakeRecoveryAttempts = 0
    private var indicatorObservation: AnyCancellable?
    private var indicatorCount = 0
    private var folderMirrorWindowIDs: Set<CGWindowID> {
        Set(folderOverlays.values.compactMap { CGWindowID(exactly: $0.panel.windowNumber) })
    }
    var borrowedAnchors = ReturnPlacement.load() {
        didSet {
            store.borrowedCount = borrowedAnchors.count
            UserDefaults.standard.set(try? JSONEncoder().encode(borrowedAnchors), forKey: "temporaryPlacements.v1")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.borrowedCount = borrowedAnchors.count
        folder = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        folder.autosaveName = "FoldMenu.Folder.v2"
        folder.button?.image = folderSymbol()
        folder.button?.target = self
        folder.button?.action = #selector(folderClicked(_:))
        folder.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installWakeRecoveryObservers()
        indicatorObservation = Publishers.CombineLatest(store.$items, store.$folderIDs)
            .map { FolderIndicator.count(availableIDs: $0.0.map(\.id), selectedIDs: $0.1) }
            .removeDuplicates()
            .sink { [weak self] count in self?.updateFolderIndicator(count: count) }

        panel.level = .popUpMenu
        panel.title = "Fold Menu Folder"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: FolderView(
            store: store,
            settings: { [weak self] in self?.openSettings() },
            activate: { [weak self] item in self?.activate(item) },
            cancel: { [weak self] in self?.menuTask?.cancel() },
            restore: { [weak self] in self?.restoreBorrowedItems() },
            refold: { [weak self] in self?.retryCollapse() }
        ).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)))

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return }
            if event.type == .keyDown {
                self.panel.orderOut(nil)
                return
            }
            // The current cursor can already be elsewhere when a hosted or
            // synthetic click reaches this monitor. Use this event's point.
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            guard FolderOutsideClickPolicy.shouldDismiss(
                eventPoint: point,
                panel: self.panel.frame,
                mirrors: self.folderOverlays.values.map { $0.panel.frame }
            ) else { return }
            trace("outside dismiss type=\(event.type.rawValue) point=\(point)")
            self.panel.orderOut(nil)
        }
        store.refresh { [weak self] in
            guard let self else { return }
            if self.store.trusted {
                self.discoveryScanPolicy.recordCompletedScan(
                    fingerprint: MenuTransport.statusWindowFingerprint(),
                    now: ProcessInfo.processInfo.systemUptime
                )
            }
            trace("startup scan items=\(self.store.items.count) selected=\(self.store.folderIDs.count) borrowed=\(self.borrowedAnchors.count) trusted=\(self.store.trusted)")
            let startupAction = BorrowedRestorePolicy.startupAction(
                layoutCompleted: UserDefaults.standard.bool(forKey: "layout.v2.completed"),
                selectedCount: self.store.folderIDs.count,
                borrowedCount: self.borrowedAnchors.count
            )
            switch startupAction {
            case .none:
                break
            case .collapse:
                self.scheduleSafeInitialCollapse()
            case .collapseAndRestoreBorrowed:
                self.scheduleSafeInitialCollapse(restoreBorrowed: true)
            }
        }
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.store.arranging, !self.wakeRecoveryInProgress else { return }
                if self.wakeRecoveryRequested {
                    guard !self.store.layoutEditing else { return }
                    self.scheduleWakeRecovery(reason: "deferred retry")
                    return
                }
                guard !self.store.layoutEditing else { return }
                if BorrowedRestorePolicy.shouldRetryInBackground(
                    hasBorrowedItems: !self.borrowedAnchors.isEmpty,
                    isArranging: self.store.arranging,
                    isEditing: self.store.layoutEditing,
                    settingsVisible: self.settingsWindow?.isVisible == true,
                    folderPanelVisible: self.panel.isVisible
                ) {
                    trace("background borrowed-item retry count=\(self.borrowedAnchors.count)")
                    self.store.refresh { [weak self] in
                        guard let self,
                              BorrowedRestorePolicy.shouldRetryInBackground(
                                hasBorrowedItems: !self.borrowedAnchors.isEmpty,
                                isArranging: self.store.arranging,
                                isEditing: self.store.layoutEditing,
                                settingsVisible: self.settingsWindow?.isVisible == true,
                                folderPanelVisible: self.panel.isVisible
                              ) else { return }
                        self.restoreBorrowedItems()
                    }
                    return
                }
                guard self.store.collapsed, !self.store.scanning else { return }
                let fingerprint = MenuTransport.statusWindowFingerprint()
                guard self.discoveryScanPolicy.shouldScan(
                    fingerprint: fingerprint,
                    now: ProcessInfo.processInfo.systemUptime,
                    trusted: self.store.trusted && AXIsProcessTrusted()
                ) else { return }
                self.store.refresh { [weak self] in
                    guard let self else { return }
                    if self.store.trusted {
                        self.discoveryScanPolicy.recordCompletedScan(
                            fingerprint: fingerprint,
                            now: ProcessInfo.processInfo.systemUptime
                        )
                        self.store.syncNewParkedItems()
                    }
                }
            }
        }
        anchorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.showFolderOverlay()
                if self.settingsNeedsPresentation { self.presentSettingsIfReady() }
                else if self.settingsWindow?.isVisible == true { self.positionSettingsUnderFolder() }
            }
        }
        if !store.trusted || CommandLine.arguments.contains("--settings") { openSettings() }
    }

    private func installWakeRecoveryObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleWakeRecovery(reason: name.rawValue) }
            }
            workspaceWakeObservers.append(observer)
        }
        applicationScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleWakeRecovery(reason: "screen parameters changed") }
        }
    }

    private func scheduleWakeRecovery(reason: String) {
        guard !store.folderIDs.isEmpty else { return }
        trace("wake recovery requested: \(reason)")
        guard !wakeRecoveryInProgress else {
            wakeRecoveryRequested = true
            anchorTracking.deferFailOpen(until: ProcessInfo.processInfo.systemUptime + 12)
            return
        }

        if !store.collapsed {
            guard !store.arranging, !store.layoutEditing,
                  settingsWindow?.isVisible != true, !panel.isVisible else {
                wakeRecoveryRequested = true
                anchorTracking.deferFailOpen(until: ProcessInfo.processInfo.systemUptime + 12)
                return
            }
            trace("wake recovery found configured folder expanded; restoring fold")
            collapse()
            anchorTracking.deferFailOpen(until: ProcessInfo.processInfo.systemUptime + 12)
            guard store.collapsed else {
                wakeRecoveryRequested = true
                return
            }
        } else {
            anchorTracking.deferFailOpen(until: ProcessInfo.processInfo.systemUptime + 12)
        }
        wakeRecoveryRequested = true

        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForStatusLayoutToSettle() else {
                trace("wake recovery deferred: status bar did not settle")
                return
            }
            guard !Task.isCancelled else { return }
            self.wakeRecoveryTask = nil
            self.beginWakeRecovery()
        }
    }

    /// WindowServer and hosted status items can rebuild asynchronously on wake.
    /// Wait for their geometry snapshot to stop changing before querying AX.
    private func waitForStatusLayoutToSettle() async -> Bool {
        var previous: Set<String>?
        var stableSamples = 0
        for _ in 0..<20 {
            guard !Task.isCancelled else { return false }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
            let current = MenuTransport.statusWindowFingerprint()
            guard !current.isEmpty else {
                previous = nil
                stableSamples = 0
                continue
            }
            stableSamples = current == previous ? stableSamples + 1 : 0
            previous = current
            if stableSamples >= 2 { return true }
        }
        return false
    }

    private func beginWakeRecovery() {
        guard wakeRecoveryRequested, store.collapsed else { return }
        guard !store.arranging, !store.layoutEditing else { return }
        store.trusted = AXIsProcessTrusted()
        guard store.trusted else {
            trace("wake recovery deferred: Accessibility is unavailable")
            return
        }

        wakeRecoveryRequested = false
        wakeRecoveryInProgress = true
        store.refresh { [weak self] in self?.evaluateWakeRecovery() }
    }

    private func evaluateWakeRecovery() {
        guard wakeRecoveryInProgress else { return }
        guard store.collapsed else {
            finishWakeRecovery()
            return
        }

        let displays = activeDisplayBounds()
        let notParkedIDs = Set(store.selected.filter {
            !MenuBarGeometry.isParkedOffscreen($0.frame, displays: displays)
        }.map(\.id))
        let runningOwners = Set(NSWorkspace.shared.runningApplications.map {
            $0.bundleIdentifier ?? $0.executableURL?.path ?? String($0.processIdentifier)
        })
        let action = FoldRecoveryPolicy.action(
            isCollapsed: store.collapsed,
            isArranging: store.arranging || store.layoutEditing,
            isTrusted: store.trusted,
            selectedIDs: store.folderIDs,
            availableIDs: Set(store.items.map(\.id)),
            runningOwners: runningOwners,
            notParkedIDs: notParkedIDs,
            borrowedIDs: Set(borrowedAnchors.keys),
            consecutiveReapplyAttempts: wakeRecoveryAttempts
        )

        switch action {
        case .none:
            trace("wake recovery verified selected=\(store.folderIDs.count) visible=0")
            store.syncNewParkedItems()
            finishWakeRecovery(resetAttempts: true)
        case .wait:
            trace("wake recovery deferred: app is busy or cannot inspect the menu bar")
            wakeRecoveryRequested = true
            finishWakeRecovery()
        case .reapply:
            trace("wake recovery found visible selected items: \(notParkedIDs.sorted())")
            wakeRecoveryAttempts += 1
            reapplyCollapsedLayout()
        case .retryLater:
            trace("wake recovery still sees visible selected items; preserving folded layout and retrying")
            store.message = "화면 복귀 후 아이콘을 다시 접는 중입니다. 잠시 후 자동으로 재시도합니다."
            wakeRecoveryRequested = true
            finishWakeRecovery(resetAttempts: true)
        case .restoreBorrowedItems:
            trace("wake recovery found borrowed selected items: \(borrowedAnchors.keys.sorted())")
            recoverBorrowedItemsAfterWake()
        }
    }

    private func recoverBorrowedItemsAfterWake() {
        guard wakeRecoveryInProgress, !store.arranging else { return }
        store.arranging = true
        store.activity = "화면 복귀 후 꺼낸 항목 복구 중…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.restoreBorrowedItemsNow()
                self.store.arranging = false
                self.store.activity = ""
                self.store.refresh { [weak self] in self?.evaluateWakeRecovery() }
            } catch {
                self.store.arranging = false
                self.store.activity = ""
                self.store.message = error.localizedDescription
                self.wakeRecoveryRequested = true
                self.finishWakeRecovery()
            }
        }
    }

    private func reapplyCollapsedLayout() {
        let lengths = FoldRecoveryPolicy.spacerLengths(current: folder.length,
                                                       collapsedLength: Self.collapsedLength)
        for length in lengths { folder.length = length }
        folder.button?.image = nil
        verifyWakeRecoveryAfterRelayout()
    }

    private func verifyWakeRecoveryAfterRelayout() {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForStatusLayoutToSettle() else {
                trace("wake recovery verification deferred: status bar did not settle")
                self.wakeRecoveryRequested = true
                self.finishWakeRecovery()
                return
            }
            guard !Task.isCancelled, self.wakeRecoveryInProgress else { return }
            self.wakeRecoveryTask = nil
            self.store.refresh { [weak self] in self?.evaluateWakeRecovery() }
        }
    }

    private func finishWakeRecovery(resetAttempts: Bool = false) {
        wakeRecoveryInProgress = false
        if resetAttempts { wakeRecoveryAttempts = 0 }
        wakeRecoveryTask = nil
    }

    private func cancelWakeRecovery() {
        wakeRecoveryTask?.cancel()
        wakeRecoveryTask = nil
        wakeRecoveryRequested = false
        wakeRecoveryInProgress = false
        wakeRecoveryAttempts = 0
    }

    private func folderSymbol() -> NSImage? {
        FolderIndicator.image(count: indicatorCount)
    }

    private func updateFolderIndicator(count: Int) {
        indicatorCount = count
        let image = FolderIndicator.image(count: count)
        for overlay in folderOverlays.values { overlay.button.image = image }
        // The expanded native item and collapsed overlay share the same glyph.
        // Never draw on the 10,000pt spacer itself.
        if !store.collapsed { folder.button?.image = image }
        let summary = "폴더 항목 \(count)개"
        let buttons = [folder.button].compactMap { $0 } + folderOverlays.values.map(\.button)
        for button in buttons {
            button.setAccessibilityLabel("Fold Menu")
            button.setAccessibilityValue(summary)
            button.toolTip = "Fold Menu — \(summary)"
        }
    }

    private func makeFolderOverlay(displayID: UInt32) -> FolderOverlay {
        let image = folderSymbol()!
        image.isTemplate = true
        let button = StatusOverlayButton(image: image, target: self, action: #selector(folderClicked(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        // This overlay sits directly on the user's current light menu bar.
        // Do not inherit the app's dark appearance, which would draw it white.
        button.contentTintColor = .black
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Fold Menu")
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 28, height: 24),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = button
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return FolderOverlay(displayID: displayID, panel: window, button: button)
    }

    private func scheduleSafeInitialCollapse(restoreBorrowed: Bool = false) {
        startupTask?.cancel()
        startupTask = Task { @MainActor [weak self] in
            var last: CGRect?
            var stable = 0
            for _ in 0..<20 {
                guard (try? await Task.sleep(for: .milliseconds(250))) != nil, let self else { return }
                let current = self.folder.button?.window?.frame
                stable = current == last ? stable + 1 : 0
                last = current
                if stable >= 2, let current, current.width >= 20, current.width <= 80 {
                    self.collapse()
                    guard restoreBorrowed, self.store.collapsed else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard await self.waitForStatusLayoutToSettle() else {
                            self.store.message = "시작할 때 메뉴바가 안정되지 않아 꺼낸 항목 복구를 보류했습니다."
                            return
                        }
                        self.restoreBorrowedItems()
                    }
                    return
                }
            }
        }
    }

    @objc private func folderClicked(_ sender: Any?) {
        trace("folder clicked collapsed=\(store.collapsed) busy=\(store.arranging)")
        let button = sender as? NSButton
        let clickedOverlay = folderOverlays.values.first { $0.button === button }
        let previousPanelDisplayID = panel.isVisible ? lastFolderAnchor?.displayID : nil
        if let clickedOverlay {
            lastFolderAnchor = (clickedOverlay.displayID, clickedOverlay.panel.frame)
        } else if let window = button?.window, let screen = window.screen,
                  let displayID = displayID(for: screen) {
            lastFolderAnchor = (displayID, window.frame)
        }
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(from: button); return }
        if store.layoutEditing {
            openSettings()
            return
        }
        let clickAction = FolderMirrorClickPolicy.action(
            panelVisible: panel.isVisible,
            panelDisplayID: previousPanelDisplayID,
            clickedDisplayID: clickedOverlay?.displayID
        )
        if clickAction == .dismiss {
            panel.orderOut(nil)
        } else if clickAction == .move, let clickedOverlay {
            showFolderPanel(anchor: clickedOverlay.panel.frame, displayID: clickedOverlay.displayID)
        } else if clickAction == .open, let clickedOverlay {
            showFolderPanel(anchor: clickedOverlay.panel.frame, displayID: clickedOverlay.displayID)
        } else if clickAction == .open {
            showFolderPanel()
        } else {
            panel.orderOut(nil)
        }
    }

    private func showContextMenu(from button: NSButton?) {
        let menu = NSMenu()
        let edit = NSMenuItem(title: store.layoutEditing ? "편집 완료하고 접기" : "폴더 항목 편집",
                              action: store.layoutEditing ? #selector(finishEditingMenu) : #selector(beginEditingMenu),
                              keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Fold Menu 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        if let button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
    }

    @objc private func beginEditingMenu() { beginLayoutEditing() }
    @objc private func finishEditingMenu() { endLayoutEditing() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showFolderPanel(anchor explicitAnchor: NSRect? = nil, displayID explicitDisplayID: UInt32? = nil) {
        let anchor: NSRect
        let targetDisplayID: UInt32?
        if let explicitAnchor, let explicitDisplayID {
            anchor = explicitAnchor
            targetDisplayID = explicitDisplayID
        } else if store.collapsed {
            let selectedOverlay = lastFolderAnchor.flatMap { folderOverlays[$0.displayID] }
                ?? folderOverlays.values.first(where: { $0.panel.isVisible })
            guard let selectedOverlay, selectedOverlay.panel.isVisible else { return }
            anchor = selectedOverlay.panel.frame
            targetDisplayID = selectedOverlay.displayID
        } else {
            guard let window = folder.button?.window else { return }
            anchor = window.frame
            targetDisplayID = window.screen.flatMap(displayID(for:))
        }
        guard let screen = targetDisplayID.flatMap(screen(for:)) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        if let targetDisplayID { lastFolderAnchor = (targetDisplayID, anchor) }
        guard let frame = folderPanelFrame(anchor: anchor, screen: screen) else { return }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func folderPanelFrame(anchor: NSRect, screen: NSScreen) -> NSRect? {
        let height: CGFloat = store.trusted && store.message.isEmpty && !store.arranging ? 128 : 210
        let size = NSSize(width: 360, height: height)
        let x = min(max(anchor.maxX - size.width, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let top = min(anchor.minY, screen.frame.maxY - NSStatusBar.system.thickness) - 6
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    private func activate(_ item: MenuItem) {
        trace("activate \(item.id) busy=\(store.arranging)")
        guard !store.arranging else { return }
        panel.orderOut(nil)
        store.arranging = true
        store.message = ""
        store.activity = "\(item.name) 여는 중…"
        menuTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.store.arranging = false
                self.store.activity = ""
                self.menuTask = nil
            }
            var returnMoveStarted = false
            do {
                try await self.ensureFolderCollapsedForOperation()
                let returnAnchor = try self.borrowedAnchors[item.id] ?? self.temporaryReturnAnchor(for: item)
                self.borrowedAnchors[item.id] = returnAnchor
                if let frame = menuElementFrame(item.element), !isInMenuBarStrip(frame) {
                    let visibleAnchor = try self.temporaryVisibleAnchor(excluding: item)
                    try await MenuTransport.move(item, leftOf: visibleAnchor.neighbor,
                                                 expecting: .visibleBeside(visibleAnchor.boundary))
                }
                try await MenuSession.pressAndWait(item) {
                    self.store.activity = "\(item.name) 메뉴 사용 중"
                }
                self.store.activity = "폴더로 되돌리는 중…"
                returnMoveStarted = true
                try await self.returnBorrowedItem(itemID: item.id)
                self.store.message = ""
            } catch {
                if !returnMoveStarted, self.borrowedAnchors[item.id] != nil {
                    do {
                        try await self.returnBorrowedItem(itemID: item.id)
                    } catch {
                        trace("activation cleanup kept borrowed item \(item.id): \(error)")
                    }
                }
                trace("activation error \(error)")
                self.store.message = error is CancellationError
                    ? "대기를 취소했습니다. 꺼낸 항목은 다시 누르면 사용할 수 있습니다."
                    : "\(error.localizedDescription) 꺼낸 항목이 있다면 다시 눌러 사용할 수 있습니다."
                self.showFolderPanel()
            }
        }
    }

    private func temporaryVisibleAnchor(excluding item: MenuItem) throws -> (neighbor: MenuTransport.Host, boundary: MenuTransport.Host) {
        guard let boundary = boundaryHost() else { throw PlacementError("폴더 위치를 확인하지 못했어요.") }
        let source = menuElementFrame(item.element).flatMap {
            MenuTransport.host(at: CGPoint(x: $0.midX, y: $0.midY))
        }
        // AX glyph bounds are not host bounds: e.g. Port Manager reports x=1249
        // while its host starts at 1250, exactly at the folder's right edge.
        // Search actual hosts, including system items and apps absent from AX.
        let candidates = MenuTransport.statusHosts().filter {
            $0.window != boundary.window && $0.window != source?.window
                && !folderMirrorWindowIDs.contains($0.window)
                && $0.visible && isInMenuBarStrip($0.frame)
                && MenuBarGeometry.isImmediatelyRight($0.frame, of: boundary.frame)
        }
        guard candidates.count == 1, let neighbor = candidates.first else {
            throw PlacementError("폴더 옆의 안전한 임시 슬롯을 찾지 못했어요.")
        }
        trace("visible slot boundary=\(boundary.window) \(boundary.frame) neighbor=\(neighbor.window) \(neighbor.frame)")
        return (neighbor, boundary)
    }

    private func ensureFolderCollapsedForOperation() async throws {
        guard !store.layoutEditing else { throw PlacementError("편집을 마친 뒤 항목을 사용해 주세요.") }
        guard !store.collapsed else { return }
        collapse()
        guard store.collapsed else {
            throw PlacementError(store.message.isEmpty ? "폴더를 접을 수 없어 항목을 사용하지 않았어요." : store.message)
        }
        store.message = ""
        guard await waitForStatusLayoutToSettle() else {
            throw PlacementError("메뉴바가 안정될 때까지 기다리지 못해 항목을 사용하지 않았어요.")
        }
    }

    private func itemIsParked(_ item: MenuItem) -> Bool {
        guard let frame = menuElementFrame(item.element),
              MenuBarGeometry.isParkedOffscreen(frame, displays: activeDisplayBounds()),
              let host = MenuTransport.host(at: CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return MenuBarGeometry.isParkedOffscreen(host.frame, displays: activeDisplayBounds())
    }

    private func returnBorrowedItem(itemID: String) async throws {
        guard let placement = borrowedAnchors[itemID] else { return }
        try await ensureFolderCollapsedForOperation()
        guard let item = store.items.first(where: { $0.id == itemID }) else {
            throw PlacementError("복귀할 메뉴바 항목을 다시 찾지 못했어요.")
        }

        switch BorrowedRestorePolicy.action(folderCollapsed: store.collapsed, itemParked: itemIsParked(item)) {
        case .collapseBeforeRestore:
            throw PlacementError("폴더를 접지 못해 항목을 되돌리지 않았어요.")
        case .alreadyInFolder:
            borrowedAnchors.removeValue(forKey: itemID)
            return
        case .moveIntoFolder:
            var pid: pid_t = 0
            AXUIElementGetPid(item.element, &pid)
            guard MenuSession.windows(for: [pid]).isEmpty else {
                throw PlacementError("\(item.name)의 메뉴를 닫고 다시 눌러 주세요.")
            }
        }

        var retries = 0
        while true {
            do {
                let destination = try resolveReturnAnchor(placement)
                try await MenuTransport.move(item, leftOf: destination.host,
                                             expecting: .hidden, afterTarget: destination.after)
                borrowedAnchors.removeValue(forKey: itemID)
                return
            } catch {
                switch BorrowedRestorePolicy.afterFailedMove(itemParked: itemIsParked(item), retries: retries) {
                case .complete:
                    borrowedAnchors.removeValue(forKey: itemID)
                    return
                case .retry:
                    retries += 1
                    guard await waitForStatusLayoutToSettle() else { throw error }
                case .keepForManualRetry:
                    throw error
                }
            }
        }
    }

    private func temporaryReturnAnchor(for item: MenuItem) throws -> ReturnPlacement {
        if let frame = menuElementFrame(item.element), isInMenuBarStrip(frame),
           let neighbor = store.selected.first(where: { $0.id != item.id && !isInMenuBarStrip($0.frame) }),
           menuElementFrame(neighbor.element) != nil {
            return ReturnPlacement(neighborID: neighbor.id, after: false)
        }
        let ordered = store.selected.sorted { $0.frame.minX < $1.frame.minX }
        if let index = ordered.firstIndex(where: { $0.id == item.id }), index + 1 < ordered.count {
            let neighbor = ordered[index + 1]
            guard let frame = menuElementFrame(neighbor.element),
                  MenuTransport.host(at: CGPoint(x: frame.midX, y: frame.midY)) != nil else {
                throw PlacementError("원래 위치의 이웃 아이콘을 찾지 못했어요.")
            }
            return ReturnPlacement(neighborID: neighbor.id, after: false)
        }
        guard boundaryHost() != nil else {
            throw PlacementError("폴더 경계의 원래 위치를 찾지 못했어요.")
        }
        return ReturnPlacement(neighborID: nil, after: false)
    }

    private func resolveReturnAnchor(_ placement: ReturnPlacement) throws -> (host: MenuTransport.Host, after: Bool) {
        if let id = placement.neighborID,
           let neighbor = store.items.first(where: { $0.id == id }),
           let frame = menuElementFrame(neighbor.element),
           !isInMenuBarStrip(frame),
           let host = MenuTransport.host(at: CGPoint(x: frame.midX, y: frame.midY)) {
            return (host, placement.after)
        }
        // A terminated neighbor cannot anchor the move; the folder boundary is
        // still valid and keeps the item inside the folder.
        guard let host = boundaryHost() else { throw PlacementError("복귀 위치를 확인하지 못했습니다.") }
        return (host, false)
    }

    private func restoreBorrowedItems() {
        guard !store.arranging else { return }
        store.arranging = true
        store.activity = "꺼낸 항목 되돌리는 중…"
        menuTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.store.arranging = false; self.store.activity = ""; self.menuTask = nil }
            do {
                try await self.restoreBorrowedItemsNow()
                self.store.message = ""
            } catch {
                self.store.message = error is CancellationError ? "복귀를 취소했습니다." : error.localizedDescription
            }
        }
    }

    private func restoreBorrowedItemsNow() async throws {
        guard !store.layoutEditing else { throw PlacementError("편집을 마친 뒤 꺼낸 항목을 되돌려 주세요.") }
        guard !borrowedAnchors.isEmpty else { return }
        trace("restore borrowed items count=\(borrowedAnchors.count) scanned=\(store.items.count)")
        try await ensureFolderCollapsedForOperation()
        for id in Array(borrowedAnchors.keys).sorted() {
            guard store.items.contains(where: { $0.id == id }) else {
                let ownerID = String(id[..<(id.lastIndex(of: ":") ?? id.endIndex)])
                let ownerIsRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == ownerID
                }
                if !ownerIsRunning {
                    trace("discard borrowed record for stopped owner: \(ownerID)")
                    borrowedAnchors.removeValue(forKey: id)
                    continue
                }
                trace("borrowed item missing from Accessibility scan: \(id)")
                throw PlacementError("꺼낸 항목을 다시 읽을 수 없어 복귀를 보류했습니다.")
            }
            try await returnBorrowedItem(itemID: id)
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(
                store: store,
                beginEditing: { [weak self] in self?.beginLayoutEditing() },
                finishEditing: { [weak self] in self?.endLayoutEditing() },
                close: { [weak self] in
                    guard let self else { return }
                    if self.store.layoutEditing { self.endLayoutEditing() }
                    self.settingsWindow?.orderOut(nil)
                },
                cancel: { [weak self] in self?.menuTask?.cancel() },
                refold: { [weak self] in self?.retryCollapse() }
            ))
            // Size to the current content, including editing/permission/error
            // messages, instead of centering it inside a fixed 340pt canvas.
            controller.sizingOptions = [.minSize, .maxSize, .preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Fold Menu"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            settingsWindow = window
        }
        settingsFollowsFolder = true
        settingsNeedsPresentation = true
        presentSettingsIfReady()
    }

    private func presentSettingsIfReady() {
        // During launch the hosted status item may not have its final frame yet.
        // Wait for the regular anchor update instead of flashing a centered window.
        guard settingsNeedsPresentation, positionSettingsUnderFolder() else { return }
        settingsNeedsPresentation = false
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        if settingsWindow?.isVisible == true { panel.orderOut(nil) }
    }

    @discardableResult
    private func positionSettingsUnderFolder() -> Bool {
        // Explicit opens must remain available while a menu is busy, including
        // the settings cancel control. Only suspend automatic following then.
        guard settingsFollowsFolder, (settingsNeedsPresentation || !store.arranging),
              NSEvent.pressedMouseButtons == 0,
              let window = settingsWindow else { return false }
        let anchor: NSRect
        let targetScreen: NSScreen?
        if store.collapsed {
            let selectedOverlay = lastFolderAnchor.flatMap { folderOverlays[$0.displayID] }
                ?? folderOverlays.values.first(where: { $0.panel.isVisible })
            guard let selectedOverlay, selectedOverlay.panel.isVisible else { return false }
            anchor = selectedOverlay.panel.frame
            targetScreen = screen(for: selectedOverlay.displayID)
        } else {
            guard let statusWindow = folder.button?.window else { return false }
            anchor = statusWindow.frame
            targetScreen = statusWindow.screen
        }
        guard anchor.width >= 20, anchor.width <= 80, anchor.height >= 18, anchor.height <= 50,
              let targetScreen,
              let origin = AnchoredWindowPlacement.origin(size: window.frame.size, anchor: anchor,
                                                          visibleFrame: targetScreen.visibleFrame) else { return false }
        if window.frame.origin != origin {
            positioningSettings = true
            window.setFrameOrigin(origin)
            positioningSettings = false
        }
        return true
    }

    private func beginLayoutEditing() {
        guard !store.arranging else { store.message = "진행 중인 메뉴 대기를 먼저 취소해 주세요."; return }
        startupTask?.cancel()
        panel.orderOut(nil)
        expand()
        store.layoutEditing = true
        store.message = "폴더 왼쪽은 폴더 안, 오른쪽은 항상 표시입니다. 앱은 아이콘을 대신 이동하지 않습니다."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.store.refresh() }
    }

    private func endLayoutEditing() {
        guard store.layoutEditing, let folderX = folder.button?.window?.frame.midX else {
            store.message = "폴더 위치를 읽지 못해 접지 않았습니다. 아이콘은 그대로 유지됩니다."
            return
        }
        store.refresh { [weak self] in
            guard let self else { return }
            self.store.captureFolderItems(leftOf: folderX)
            self.borrowedAnchors.removeAll()
            self.store.layoutEditing = false
            if self.store.folderIDs.isEmpty {
                self.store.message = "폴더 왼쪽에 배치된 항목이 없어 펼친 상태를 유지합니다."
                self.expand()
            } else {
                self.store.message = "폴더 항목 \(self.store.folderIDs.count)개를 접었습니다."
                self.collapse()
            }
        }
    }

    private func retryCollapse() {
        guard !store.arranging, !store.layoutEditing else { return }
        startupTask?.cancel()
        store.message = ""
        collapse()
    }

    private func collapse() {
        guard !store.collapsed, !store.layoutEditing, !store.folderIDs.isEmpty else { return }
        guard let anchor = folder.button?.window?.frame,
              anchor.width >= 20, anchor.width <= 80,
              anchor.height >= 18, anchor.height <= 50 else {
            // Never turn a stale 5,000pt spacer frame into an overlay window.
            // Staying expanded is safer than covering the user's screen.
            hideFolderOverlays()
            store.collapsed = false
            store.message = "폴더 위치가 안정되지 않아 접기를 보류했습니다."
            expand()
            return
        }
        cancelWakeRecovery()
        // Keep the visible folder exactly where the real status item was before
        // its invisible spacer grows. The enlarged status window's frame is not
        // a stable anchor and can jump across the menu bar.
        expandedFolderFrame = anchor
        // Learn the real host identity BEFORE resizing it. The AppKit proxy may
        // subsequently report the old 38pt width, even though the spacer exists.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let quartz = CGRect(x: anchor.minX, y: primaryTop - anchor.maxY, width: anchor.width, height: anchor.height)
        let initial = MenuTransport.statusHosts().filter {
            !folderMirrorWindowIDs.contains($0.window)
                && abs($0.frame.minX - quartz.minX) < 1 && abs($0.frame.minY - quartz.minY) < 1
                && abs($0.frame.width - quartz.width) < 1 && abs($0.frame.height - quartz.height) < 1
        }
        anchorTracking.begin(host: initial.count == 1 ? initial.first.map {
            FolderAnchorTracking.Window(id: $0.window, pid: $0.pid, frame: $0.frame)
        } : nil)
        trace("collapse anchor=\(anchor) host=\(String(describing: anchorTracking.host))")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            folder.length = Self.collapsedLength
        }
        folder.button?.image = nil
        store.collapsed = true
        DispatchQueue.main.async { [weak self] in
            self?.showFolderOverlay()
            trace("collapsed native=\(String(describing: self?.folder.button?.window?.frame)) boundary=\(String(describing: self?.boundaryHost()?.frame)) mirrors=\(String(describing: self?.folderOverlays.mapValues(\.panel.frame)))")
        }
    }

    private func expand() {
        cancelWakeRecovery()
        anchorTracking.begin(host: nil)
        hideFolderOverlays()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            folder.length = NSStatusItem.squareLength
        }
        folder.button?.image = folderSymbol()
        store.collapsed = false
        DispatchQueue.main.async { [weak self] in
            self?.expandedFolderFrame = self?.folder.button?.window?.frame
        }
    }

    private func mirrorDisplays() -> [(id: UInt32, bounds: CGRect)] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else { return nil }
            let bounds = CGDisplayBounds(CGDirectDisplayID(id))
            guard !bounds.isEmpty, !bounds.isNull, !bounds.isInfinite else { return nil }
            return (id, bounds)
        }
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { self.displayID(for: $0) == displayID }
    }

    private func hideFolderOverlays() {
        for overlay in folderOverlays.values { overlay.panel.orderOut(nil) }
    }

    private func removeDisconnectedFolderOverlays(activeDisplayIDs: Set<UInt32>) {
        let removedIDs = folderOverlays.keys.filter { !activeDisplayIDs.contains($0) }
        for displayID in removedIDs {
            folderOverlays[displayID]?.panel.orderOut(nil)
            folderOverlays.removeValue(forKey: displayID)
        }
    }

    private func showFolderOverlay() {
        guard store.collapsed, let anchor = expandedFolderFrame else {
            hideFolderOverlays()
            return
        }
        guard anchor.width >= 20, anchor.width <= 80,
              anchor.height >= 18, anchor.height <= 50 else {
            hideFolderOverlays()
            expand()
            return
        }
        let displays = mirrorDisplays()
        removeDisconnectedFolderOverlays(activeDisplayIDs: Set(displays.map(\.id)))
        let hosts = MenuTransport.statusHosts().filter { !folderMirrorWindowIDs.contains($0.window) }
        let host = boundaryHost(in: hosts)
        guard let host else {
            hideFolderOverlays()
            if anchorTracking.missingSince == nil {
                trace("anchor missing native=\(String(describing: folder.button?.window?.frame)) known=\(String(describing: anchorTracking.host)) displays=\(activeDisplayBounds())")
            }
            if anchorTracking.shouldFailOpen(at: ProcessInfo.processInfo.systemUptime) {
                menuTask?.cancel()
                store.message = "폴더 위치를 확인하지 못해 메뉴바를 펼쳤습니다. ‘다시 접기’를 눌러 재시도할 수 있습니다."
                trace("anchor unavailable for 2s; expanding native=\(String(describing: folder.button?.window?.frame)) hosts=\(MenuTransport.statusHosts().filter { $0.frame.width > 1000 })")
                expand()
            }
            return
        }
        if anchorTracking.missingSince != nil { trace("anchor recovered host=\(host.window) frame=\(host.frame)") }

        let displayDescriptions = displays.map { MenuBarMirrorPlacement.Display(id: $0.id, bounds: $0.bounds) }
        let nativeDisplayID = MenuBarMirrorPlacement.displayID(forStatusHost: host.frame, among: displayDescriptions)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let frames = MenuBarMirrorPlacement.frames(
            displays: displayDescriptions,
            statusHosts: hosts.map { MenuBarMirrorPlacement.StatusHost(id: $0.window, pid: $0.pid, frame: $0.frame) },
            trackedHostID: host.window,
            trackedHostPID: host.pid,
            cocoaPrimaryTop: primaryTop,
            iconSize: CGSize(width: min(anchor.width, 44), height: min(anchor.height, 44))
        )
        guard let nativeDisplayID, frames[nativeDisplayID] != nil else {
            hideFolderOverlays()
            if MenuBarMirrorPlacement.isTemporarilyHidden(host.frame, among: displayDescriptions) {
                anchorTracking.found()
                return
            }
            trace("native menu-bar reservation could not be mapped to a display; screens=\(displayDescriptions) host=\(host.frame)")
            if anchorTracking.shouldFailOpen(at: ProcessInfo.processInfo.systemUptime) {
                store.message = "폴더 아이콘을 놓을 메뉴바 위치를 확인하지 못해 펼쳤습니다. 다시 접기를 눌러 재시도할 수 있습니다."
                expand()
            }
            return
        }
        anchorTracking.found()

        let activeIDs = Set(frames.keys)
        removeDisconnectedFolderOverlays(activeDisplayIDs: Set(displays.map(\.id)))
        let unmappedIDs = folderOverlays.keys.filter { !activeIDs.contains($0) }
        for displayID in unmappedIDs {
            folderOverlays[displayID]?.panel.orderOut(nil)
            folderOverlays.removeValue(forKey: displayID)
        }

        let activeDisplayID = (NSScreen.main ?? NSScreen.screens.first).flatMap(displayID(for:))
        for (displayID, frame) in frames {
            let overlay = folderOverlays[displayID] ?? makeFolderOverlay(displayID: displayID)
            folderOverlays[displayID] = overlay
            let opacity = FolderMirrorAppearance.opacity(displayID: displayID, activeDisplayID: activeDisplayID)
            if overlay.button.alphaValue != opacity { overlay.button.alphaValue = opacity }
            if overlay.panel.frame != frame { overlay.panel.setFrame(frame, display: true) }
            if !overlay.panel.isVisible { overlay.panel.orderFrontRegardless() }
            if lastFolderAnchor?.displayID == displayID { lastFolderAnchor = (displayID, frame) }
        }
        let lastDisplayIsActive = lastFolderAnchor.map { activeIDs.contains($0.displayID) } ?? false
        if !lastDisplayIsActive, let frame = frames[nativeDisplayID] {
            lastFolderAnchor = (nativeDisplayID, frame)
        }
        if panel.isVisible,
           let selected = lastFolderAnchor,
           let updated = frames[selected.displayID],
           let screen = screen(for: selected.displayID),
           let panelFrame = folderPanelFrame(anchor: updated, screen: screen),
           panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: true)
        }
        trace("mirrors updated displays=\(frames.keys.sorted()) native=\(nativeDisplayID) frames=\(frames)")
    }

    private func boundaryHost(in suppliedHosts: [MenuTransport.Host]? = nil) -> MenuTransport.Host? {
        let quartz: CGRect?
        if let frame = folder.button?.window?.frame, let primary = NSScreen.screens.first {
            quartz = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        } else {
            quartz = nil
        }
        let hosts = suppliedHosts ?? MenuTransport.statusHosts().filter { !folderMirrorWindowIDs.contains($0.window) }
        guard let match = anchorTracking.resolve(reportedFrame: quartz, candidates: hosts.map {
            FolderAnchorTracking.Window(id: $0.window, pid: $0.pid, frame: $0.frame)
        }) else { return nil }
        return hosts.first { $0.window == match.id && $0.pid == match.pid }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsNeedsPresentation = false
            if store.layoutEditing { endLayoutEditing() }
        }
    }

    func windowWillMove(_ notification: Notification) {
        // A deliberate user drag is allowed. Reopening settings attaches it again.
        if notification.object as? NSWindow === settingsWindow, !positioningSettings {
            settingsFollowsFolder = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CursorTransaction.finishActive()
        discoveryTimer?.invalidate()
        anchorTimer?.invalidate()
        wakeRecoveryTask?.cancel()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceWakeObservers { workspaceCenter.removeObserver(observer) }
        workspaceWakeObservers.removeAll()
        if let applicationScreenObserver {
            NotificationCenter.default.removeObserver(applicationScreenObserver)
            self.applicationScreenObserver = nil
        }
        expand()
        hideFolderOverlays()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        menuTask?.cancel()
        startupTask?.cancel()
        UserDefaults.standard.synchronize()
    }
}

if CommandLine.arguments.contains("--scan-diagnose") {
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "required")")
    for runningApp in NSWorkspace.shared.runningApplications where runningApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
        let root = AXUIElementCreateApplication(runningApp.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let value = attribute(root, kAXExtrasMenuBarAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
        let children = attribute(value as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for (index, child) in children.enumerated() {
            let frame = menuElementFrame(child).map { NSStringFromRect($0) } ?? "no-frame"
            let title = attribute(child, kAXTitleAttribute) as? String ?? ""
            print("\(runningApp.bundleIdentifier ?? "no-bundle") [\(index)] \(frame) \(title)")
        }
    }
} else if CommandLine.arguments.contains("--diagnose") {
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "required")")
    print("Menu-bar mode: one folder item; manual horizontal editing only")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
