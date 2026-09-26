import CoreGraphics

enum FoldRecoveryPolicy {
    enum Action: Equatable {
        case none
        case wait
        case reapply
        case retryLater
        case restoreBorrowedItems
    }

    static func action(isCollapsed: Bool,
                       isArranging: Bool,
                       isTrusted: Bool,
                       selectedIDs: Set<String>,
                       availableIDs: Set<String>? = nil,
                       runningOwners: Set<String> = [],
                       notParkedIDs: Set<String>,
                       borrowedIDs: Set<String> = [],
                       consecutiveReapplyAttempts: Int = 0,
                       maximumImmediateAttempts: Int = 2) -> Action {
        guard isCollapsed, !selectedIDs.isEmpty else { return .none }
        guard !isArranging, isTrusted else { return .wait }
        guard selectedIDs.isDisjoint(with: borrowedIDs) else { return .restoreBorrowedItems }
        if let availableIDs, selectedIDs.subtracting(availableIDs).contains(where: { id in
            guard let separator = id.lastIndex(of: ":") else { return false }
            return runningOwners.contains(String(id[..<separator]))
        }) { return .wait }
        guard !selectedIDs.isDisjoint(with: notParkedIDs) else { return .none }
        return consecutiveReapplyAttempts >= maximumImmediateAttempts ? .retryLater : .reapply
    }

    static func spacerLengths(current: CGFloat, collapsedLength: CGFloat) -> [CGFloat] {
        if abs(current - collapsedLength) < 0.5 {
            return [collapsedLength - 1, collapsedLength]
        }
        return [collapsedLength]
    }
}

enum BorrowedRestorePolicy {
    enum StartupAction: Equatable {
        case none
        case collapse
        case collapseAndRestoreBorrowed
    }

    enum Action: Equatable {
        case collapseBeforeRestore
        case alreadyInFolder
        case moveIntoFolder
    }

    enum FailedMoveAction: Equatable {
        case complete
        case retry
        case keepForManualRetry
    }

    static func action(folderCollapsed: Bool, itemParked: Bool) -> Action {
        guard folderCollapsed else { return .collapseBeforeRestore }
        return itemParked ? .alreadyInFolder : .moveIntoFolder
    }

    static func startupAction(layoutCompleted: Bool, selectedCount: Int, borrowedCount: Int) -> StartupAction {
        guard layoutCompleted, selectedCount > 0 else { return .none }
        return borrowedCount > 0 ? .collapseAndRestoreBorrowed : .collapse
    }

    static func afterFailedMove(itemParked: Bool, retries: Int, maximumRetries: Int = 1) -> FailedMoveAction {
        if itemParked { return .complete }
        return retries < maximumRetries ? .retry : .keepForManualRetry
    }

    static func shouldRetryInBackground(hasBorrowedItems: Bool,
                                        isArranging: Bool,
                                        isEditing: Bool,
                                        settingsVisible: Bool,
                                        folderPanelVisible: Bool) -> Bool {
        // The folder panel may be showing the failed-return error. Keeping it
        // open must not strand the icon outside the folder indefinitely.
        hasBorrowedItems && !isArranging && !isEditing && !settingsVisible
    }
}
