import CoreGraphics

enum MenuBarMirrorPlacementTests {
    static func run() {
        typealias Display = MenuBarMirrorPlacement.Display
        typealias Host = MenuBarMirrorPlacement.StatusHost

        let main = Display(id: 1, bounds: CGRect(x: 0, y: 0, width: 1800, height: 1169))
        let upper = Display(id: 4, bounds: CGRect(x: -197, y: -1080, width: 1920, height: 1080))
        let mainSpacer = Host(id: 101, pid: 16695, frame: CGRect(x: -3773, y: 0, width: 5016, height: 39))
        let upperSpacer = Host(id: 202, pid: 16695, frame: CGRect(x: -3852, y: -1080, width: 5016, height: 30))
        let ordinaryItem = Host(id: 303, pid: 16695, frame: CGRect(x: 1243, y: 0, width: 47, height: 39))
        let wrongRow = Host(id: 404, pid: 16695, frame: CGRect(x: -3773, y: 90, width: 5016, height: 39))
        precondition(MenuBarMirrorPlacement.displayID(forStatusHost: upperSpacer.frame, among: [main, upper]) == 4,
                     "The native reservation must map to the display whose menu-bar row contains it")
        let autoHiddenSpacer = Host(id: 101, pid: 16695,
                                    frame: CGRect(x: -3773, y: -39, width: 5016, height: 39))
        precondition(MenuBarMirrorPlacement.isTemporarilyHidden(autoHiddenSpacer.frame, among: [main, upper]),
                     "An auto-hidden menu-bar reservation must not be mistaken for a lost folder")
        precondition(!MenuBarMirrorPlacement.isTemporarilyHidden(mainSpacer.frame, among: [main, upper]),
                     "A visible reservation must continue through normal overlay placement")
        precondition(!MenuBarMirrorPlacement.isTemporarilyHidden(wrongRow.frame, among: [main, upper]),
                     "An unrelated status window must not disable anchor recovery")

        let frames = MenuBarMirrorPlacement.frames(
            displays: [main, upper], statusHosts: [mainSpacer, upperSpacer, ordinaryItem, wrongRow],
            trackedHostID: 202, trackedHostPID: 16695,
            cocoaPrimaryTop: 1169, iconSize: CGSize(width: 38, height: 39)
        )

        precondition(frames[1] == CGRect(x: 1205, y: 1130, width: 38, height: 39),
                     "A main-display mirror must align to that display's reserved status-item slot")
        precondition(frames[4] == CGRect(x: 1126, y: 2219, width: 38, height: 30),
                     "A vertically offset display must get its own correctly converted menu-bar frame")

        let shortNativeAnchorFrames = MenuBarMirrorPlacement.frames(
            displays: [main, upper], statusHosts: [mainSpacer, upperSpacer],
            trackedHostID: 202, trackedHostPID: 16695,
            cocoaPrimaryTop: 1169, iconSize: CGSize(width: 38, height: 30)
        )
        precondition(shortNativeAnchorFrames[1] == CGRect(x: 1205, y: 1130, width: 38, height: 39),
                     "A 30pt native anchor must not push the folder glyph down in a 39pt menu bar")
        precondition(shortNativeAnchorFrames[4] == CGRect(x: 1126, y: 2219, width: 38, height: 30),
                     "The 30pt menu bar must keep its own local height")

        let disconnected = MenuBarMirrorPlacement.frames(
            displays: [main], statusHosts: [mainSpacer, upperSpacer], trackedHostID: 202, trackedHostPID: 16695,
            cocoaPrimaryTop: 1169, iconSize: CGSize(width: 38, height: 39)
        )
        precondition(disconnected.count == 1 && disconnected[1] != nil,
                     "Removing a display must remove only its mirror, not the connected display's")

        let ambiguous = MenuBarMirrorPlacement.frames(
            displays: [main, upper], statusHosts: [mainSpacer, upperSpacer,
                Host(id: 203, pid: 16695, frame: CGRect(x: -3900, y: -1080, width: 5100, height: 30))],
            trackedHostID: nil, trackedHostPID: 16695,
            cocoaPrimaryTop: 1169, iconSize: CGSize(width: 38, height: 39)
        )
        precondition(ambiguous[1] != nil && ambiguous[4] == nil,
                     "An ambiguous untracked slot must be skipped rather than covering a menu-bar item")

        let foreignOwnerOnly = MenuBarMirrorPlacement.frames(
            displays: [main, upper], statusHosts: [mainSpacer,
                Host(id: 204, pid: 17777, frame: upperSpacer.frame)],
            trackedHostID: 101, trackedHostPID: 16695,
            cocoaPrimaryTop: 1169, iconSize: CGSize(width: 38, height: 39)
        )
        precondition(foreignOwnerOnly[1] != nil && foreignOwnerOnly[4] == nil,
                     "A foreign process reservation must never be mistaken for this app's mirror slot")

        precondition(FolderMirrorClickPolicy.action(panelVisible: false, panelDisplayID: nil,
                                                   clickedDisplayID: 4) == .open,
                     "Clicking a folder mirror while closed must open the shared folder panel")
        precondition(FolderMirrorClickPolicy.action(panelVisible: true, panelDisplayID: 4,
                                                   clickedDisplayID: 4) == .dismiss,
                     "Clicking the same display mirror must dismiss the panel")
        precondition(FolderMirrorClickPolicy.action(panelVisible: true, panelDisplayID: 4,
                                                   clickedDisplayID: 1) == .move,
                     "Clicking another display mirror must move the open panel to that display")
        precondition(FolderMirrorAppearance.opacity(displayID: 1, activeDisplayID: 1) == 1,
                     "The active screen's folder icon must remain fully legible")
        precondition(FolderMirrorAppearance.opacity(displayID: 4, activeDisplayID: 1) < 0.5,
                     "An inactive screen's folder icon must dim like neighboring menu-bar icons")
        precondition(FolderMirrorAppearance.opacity(displayID: 4, activeDisplayID: 4) == 1,
                     "The same icon must become fully legible after screen focus changes")
        precondition(FolderMirrorAppearance.opacity(displayID: 1, activeDisplayID: 4) < 0.5,
                     "The formerly active screen must dim after focus changes")
        let folderPanel = CGRect(x: 1490, y: 100, width: 360, height: 105)
        let folderMirror = CGRect(x: 1812, y: 211, width: 38, height: 30)
        precondition(!FolderOutsideClickPolicy.shouldDismiss(eventPoint: CGPoint(x: 1830, y: 225),
                                                             panel: folderPanel, mirrors: [folderMirror]),
                     "The mirror click's own position, not a separately moved cursor, must preserve the panel")
        precondition(!FolderOutsideClickPolicy.shouldDismiss(eventPoint: CGPoint(x: 1500, y: 120),
                                                             panel: folderPanel, mirrors: [folderMirror]),
                     "Clicks inside the folder panel must not dismiss it")
        precondition(FolderOutsideClickPolicy.shouldDismiss(eventPoint: CGPoint(x: 100, y: 100),
                                                            panel: folderPanel, mirrors: [folderMirror]),
                     "A genuine outside click still dismisses the folder")
        print("PASS: per-display placement, ownership filtering, and click behavior")
    }
}
