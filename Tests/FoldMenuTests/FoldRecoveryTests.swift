enum FoldRecoveryTests {
    static func run() {
        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: true,
            selectedIDs: ["docker", "holdimg"],
            notParkedIDs: ["holdimg"],
            borrowedIDs: [],
            consecutiveReapplyAttempts: 0
        ) == .reapply, "A selected icon that reappears after wake requests recovery")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: true,
            selectedIDs: ["docker", "holdimg"],
            notParkedIDs: ["holdimg"],
            borrowedIDs: [],
            consecutiveReapplyAttempts: 2
        ) == .retryLater, "Exhausting immediate wake retries must preserve the folder and schedule another recovery")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: true,
            selectedIDs: ["docker", "holdimg"],
            notParkedIDs: ["holdimg"],
            borrowedIDs: ["holdimg"],
            consecutiveReapplyAttempts: 0
        ) == .restoreBorrowedItems, "Wake recovery must restore an outstanding borrowed item before judging collapse")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: true,
            selectedIDs: ["docker", "holdimg"],
            notParkedIDs: []
        ) == .none, "Already parked selected items are left alone")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true, isArranging: false, isTrusted: true,
            selectedIDs: ["com.example.Docker:0", "com.example.HoldImg:0"],
            availableIDs: ["com.example.Docker:0"], runningOwners: ["com.example.Docker", "com.example.HoldImg"],
            notParkedIDs: []
        ) == .wait, "A missing AX result from a running selected app must not count as a verified fold")
        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true, isArranging: false, isTrusted: true,
            selectedIDs: ["com.example.Docker:0", "com.example.HoldImg:0"],
            availableIDs: ["com.example.Docker:0"], runningOwners: ["com.example.Docker"],
            notParkedIDs: []
        ) == .none, "A selected app that is no longer running does not hold up wake recovery")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: false,
            isArranging: false,
            isTrusted: true,
            selectedIDs: ["docker"],
            notParkedIDs: ["docker"]
        ) == .none, "Expanded folders must not be collapsed by a wake callback")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: true,
            isTrusted: true,
            selectedIDs: ["docker"],
            notParkedIDs: ["docker"]
        ) == .wait, "Recovery waits while menu layout is being edited")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: false,
            selectedIDs: ["docker"],
            notParkedIDs: ["docker"]
        ) == .wait, "Recovery waits until Accessibility can verify the real menu bar")

        precondition(FoldRecoveryPolicy.action(
            isCollapsed: true,
            isArranging: false,
            isTrusted: true,
            selectedIDs: [],
            notParkedIDs: ["docker"]
        ) == .none, "An empty folder has nothing to recover")

        precondition(FoldRecoveryPolicy.spacerLengths(current: 10_000, collapsedLength: 10_000)
            == [9_999, 10_000], "A collapsed spacer gets a distinct width to force menu-bar relayout")
        precondition(FoldRecoveryPolicy.spacerLengths(current: 9_999, collapsedLength: 10_000)
            == [10_000], "A spacer already nudged away from its target returns to the target width")

        precondition(BorrowedRestorePolicy.action(folderCollapsed: false, itemParked: false)
            == .collapseBeforeRestore, "An unfolded folder must be re-collapsed before resolving a borrowed item's return slot")
        precondition(BorrowedRestorePolicy.action(folderCollapsed: true, itemParked: false)
            == .moveIntoFolder, "A visible borrowed item in a collapsed folder needs a verified return move")
        precondition(BorrowedRestorePolicy.action(folderCollapsed: true, itemParked: true)
            == .alreadyInFolder, "An item already parked by collapse should only clear its borrowed record")
        precondition(BorrowedRestorePolicy.afterFailedMove(itemParked: false, retries: 0)
            == .retry, "A failed return move should settle and retry once before leaving the item out")
        precondition(BorrowedRestorePolicy.afterFailedMove(itemParked: true, retries: 0)
            == .complete, "A failed verification should count as success if the icon actually reached the folder")
        precondition(BorrowedRestorePolicy.afterFailedMove(itemParked: false, retries: 1)
            == .keepForManualRetry, "A second failed move should stop and preserve the borrowed record")
        precondition(BorrowedRestorePolicy.startupAction(layoutCompleted: true, selectedCount: 6, borrowedCount: 1)
            == .collapseAndRestoreBorrowed, "Startup should re-collapse the chosen folder and recover outstanding items")
        precondition(BorrowedRestorePolicy.startupAction(layoutCompleted: true, selectedCount: 6, borrowedCount: 0)
            == .collapse, "A completed nonempty folder still receives its normal startup collapse")
        precondition(BorrowedRestorePolicy.startupAction(layoutCompleted: false, selectedCount: 6, borrowedCount: 1)
            == .none, "A folder that the user has not configured must not be changed at startup")
        precondition(BorrowedRestorePolicy.shouldRetryInBackground(
            hasBorrowedItems: true, isArranging: false, isEditing: false,
            settingsVisible: false, folderPanelVisible: false
        ), "A borrowed item that could not be read at startup must be retried after later menu scans")
        precondition(!BorrowedRestorePolicy.shouldRetryInBackground(
            hasBorrowedItems: true, isArranging: true, isEditing: false,
            settingsVisible: false, folderPanelVisible: false
        ), "Background recovery must not overlap an active menu operation")
        precondition(!BorrowedRestorePolicy.shouldRetryInBackground(
            hasBorrowedItems: true, isArranging: false, isEditing: true,
            settingsVisible: false, folderPanelVisible: false
        ), "Background recovery must not interfere with layout editing")
        precondition(!BorrowedRestorePolicy.shouldRetryInBackground(
            hasBorrowedItems: true, isArranging: false, isEditing: false,
            settingsVisible: true, folderPanelVisible: false
        ), "Background recovery must wait while settings are open")
        precondition(BorrowedRestorePolicy.shouldRetryInBackground(
            hasBorrowedItems: true, isArranging: false, isEditing: false,
            settingsVisible: false, folderPanelVisible: true
        ), "An error panel must not block automatic return of a borrowed item")
        print("PASS: wake recovery policy")
    }
}
