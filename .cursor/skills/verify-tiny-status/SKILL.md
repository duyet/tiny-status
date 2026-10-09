---
name: verify-tiny-status
description: Drive the TinyStatus macOS AppKit app the way a user does. Use after UI or config changes (density, toolbar menus, column sort, check actions) to launch, doctor, exercise one mapped feature, and keep proof artifacts.
---

# Verify TinyStatus

TinyStatus is a local AppKit health-check window plus menu bar. Primary surface: the main outline table and unified toolbar. Secondary: Settings, Import, menu bar.

## Launch

From the repo root:

```bash
make app
open TinyStatus.app
```

Ready when process `TinyStatus` is running and a window titled `TinyStatus` exists:

```bash
pgrep -x TinyStatus
osascript -e 'tell application "System Events" to (name of windows of process "TinyStatus")'
```

Teardown only what this run started:

```bash
osascript -e 'tell application "TinyStatus" to quit'
# if it ignores Apple Events:
kill "$(pgrep -nx TinyStatus)"
```

Do not `killall TinyStatus` — that can take the user's own instance. Prefer a disposable config:

```bash
export TINYSTATUS_VERIFY=1
```

The app still reads `~/.config/tiny-status/tunnels.json`. Do not overwrite the user's live file. Drive UI on the running build; use `tunnels.example.json` only as a read-only schema reference.

## Doctor

```bash
test -x TinyStatus.app/Contents/MacOS/TinyStatus
defaults read net.duyet.tiny-status TinyStatus.density || true
pgrep -l -x TinyStatus
```

Worth driving only if the binary is the one `make app` just wrote (mtime of `TinyStatus.app/Contents/MacOS/TinyStatus` is recent) and a window is visible.

This app is a single shared instance. Do not launch a second copy while the user is using TinyStatus. If a copy is already running that you did not start, skip live drive and report the skip.

## Drive

Harness: Accessibility via `osascript` / System Events, plus `screencapture`. There is no HTTP debug port.

Stable handles:

- Window: process `TinyStatus`, window 1
- Toolbar menu buttons: Status, Group, Density, Columns (no Sort)
- Table: outline view; sort by clicking column headers (Check, Type, Status, Tags, Latency, Version, Target)
- Row actions: buttons in the Actions column; right-click row menu
- Menu: View → Density / Filter Status / Group By (checked item = current)

Prefer AX titles over coordinates. Example: open Density and read menu item states:

```applescript
tell application "System Events"
  tell process "TinyStatus"
    set frontmost to true
    click menu bar item "View" of menu bar 1
    click menu item "Density" of menu "View" of menu bar 1
    get {name, value} of menu items of menu "Density" of menu item "Density" of menu "View" of menu bar 1
  end tell
end tell
```

## Evidence

Write under `.cursor/skills/verify-tiny-status/evidence/<YYYY-MM-DD>-<feature>/`. Keep after cleanup.

- Screenshot of the window after the action (`screencapture -l <windowid>`)
- osascript output (menu item checkmarks, row titles)
- Note UserDefaults `TinyStatus.density` after a density change

Proof standards: click the real toolbar/menu/header, then observe the resulting checkmark, row size, or sort indicator. Do not set Store fields from a test harness.

## Cleanup

Quit the instance this run opened. Leave `evidence/` in place. Do not delete `~/.config/tiny-status/tunnels.json`.

## Helpers

```bash
.cursor/skills/verify-tiny-status/scripts/doctor.sh
.cursor/skills/verify-tiny-status/scripts/screenshot.sh <feature-id>
```
