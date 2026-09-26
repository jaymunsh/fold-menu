# Multi-monitor Fold Menu verification — 2026-09-23

## Setup

- macOS 26.6.2, Apple M1 Max
- Built-in Liquid Retina XDR (`displayID 1`) and V28UE-M (`displayID 4`), both online and not mirrored
- App relaunched from `dist/Fold Menu.app` after `bash scripts/build.sh`
- Permission toggles were not changed during this verification.

## Live window inventory

Command: `swift scripts/verify-mirrors.swift`

```text
pid=26113 screens=[1, 4] nativeStatusItems=1 mirrors=[(1, (1177.0, 0.0, 38.0, 39.0)), (4, (1098.0, -1080.0, 38.0, 30.0))]
folderPanel=hidden
```

`nativeStatusItems=1` confirms the app did not add a second native menu-bar item. Each connected display had one app-owned clickable mirror window.

## Click behavior

Open from built-in display (`swift scripts/verify-mirrors.swift 1`):

```text
AXPress display=1 result=0
pid=26113 screens=[1, 4] nativeStatusItems=1 mirrors=[(1, (1177.0, 0.0, 38.0, 39.0)), (4, (1098.0, -1080.0, 38.0, 30.0))]
folderPanel=visible display=1 frame=(855.0, 45.0, 360.0, 140.0)
```

With the panel open, press the external display mirror (`swift scripts/verify-mirrors.swift 4`):

```text
AXPress display=4 result=0
pid=26113 screens=[1, 4] nativeStatusItems=1 mirrors=[(1, (1177.0, 0.0, 38.0, 39.0)), (4, (1098.0, -1080.0, 38.0, 30.0))]
folderPanel=visible display=4 frame=(776.0, -1044.0, 360.0, 140.0)
```

Press display 4 again:

```text
AXPress display=4 result=0
pid=26113 screens=[1, 4] nativeStatusItems=1 mirrors=[(1, (1177.0, 0.0, 38.0, 39.0)), (4, (1098.0, -1080.0, 38.0, 30.0))]
folderPanel=hidden
```

## Automated checks

`bash scripts/test.sh` passed all 11 test groups, including same-PID host selection and cross-display open/move/dismiss policy. `swift build -c release` and `bash scripts/build.sh` passed; the latter verified the app signature. `git diff --check` passed.

## Not covered

Physical monitor disconnect/reconnect and macOS 27 have not been tested. Placement is intentionally skipped for a display if a same-process menu-bar reservation cannot be identified uniquely.
