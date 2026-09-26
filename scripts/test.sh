#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc Sources/FoldMenu/Selection.swift Sources/FoldMenu/MenuBarGeometry.swift Sources/FoldMenu/MenuBarMirrorPlacement.swift Sources/FoldMenu/MenuSessionPolicy.swift Sources/FoldMenu/CursorMotion.swift Sources/FoldMenu/FolderIndicator.swift Sources/FoldMenu/NativeMenuPress.swift Sources/FoldMenu/MenuPlacementSettling.swift Sources/FoldMenu/StatusWindowFingerprint.swift Sources/FoldMenu/DiscoveryScanPolicy.swift Sources/FoldMenu/AnchoredWindowPlacement.swift Sources/FoldMenu/FolderAnchorTracking.swift Sources/FoldMenu/FoldRecoveryPolicy.swift \
  Tests/FoldMenuTests/SelectionTests.swift Tests/FoldMenuTests/MenuBarGeometryTests.swift Tests/FoldMenuTests/MenuBarMirrorPlacementTests.swift Tests/FoldMenuTests/MenuSessionTests.swift Tests/FoldMenuTests/CursorMotionTests.swift Tests/FoldMenuTests/FolderIndicatorTests.swift Tests/FoldMenuTests/NativeMenuPressTests.swift Tests/FoldMenuTests/MenuPlacementSettlingTests.swift Tests/FoldMenuTests/StatusWindowFingerprintTests.swift Tests/FoldMenuTests/DiscoveryScanPolicyTests.swift Tests/FoldMenuTests/AnchoredWindowPlacementTests.swift Tests/FoldMenuTests/FolderAnchorTrackingTests.swift Tests/FoldMenuTests/FoldRecoveryTests.swift \
  -o .build/checks/selection-tests
.build/checks/selection-tests
