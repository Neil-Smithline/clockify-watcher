# ClockifyWatcher

macOS menubar app that shows the active Clockify timer in the status bar and lets you switch projects or stop the timer from the menu.

## Architecture

Pure AppKit / Swift — no SwiftUI, no third-party dependencies.

| File | Responsibility |
|------|---------------|
| `main.swift` | App entry point |
| `AppDelegate.swift` | Status item, polling, menu, system event handling |
| `ClockifyClient.swift` | API models + networking (URLSession) |
| `KeychainHelper.swift` | Keychain save / load / delete |
| `Formatting.swift` | `formatElapsed(from:)`, `NSColor(hex:)` |

Key decisions:
- Polling: 30 s for API state, 1 s display timer for elapsed-time tick
- Menu is rebuilt synchronously in `menuWillOpen` (not on a timer)
- `stopTimerSync` bridges async → sync via `DispatchSemaphore` for notification handlers that must return before the OS proceeds (sleep, lock, power-off)
- `SMAppService.mainApp.register()` is called every launch — it is idempotent and only takes effect when the app runs from `/Applications`
- Xcode project file (`project.pbxproj`) is maintained by hand; UUID prefix convention: `AA*` base, `BB*` Keychain, `CC*` Client, `DD*` Formatting, `EE*` future frameworks
- Bundle ID: `com.clockify.ClockifyWatcher`, deployment target: macOS 11.0

## Building

```bash
# Build
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build build

# Test
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test
```

## TODO

### Needs manual testing
- [x] Stop timer on Mac sleep (`NSWorkspace.willSleepNotification`)
- [x] Stop timer on screen lock (`com.apple.screenIsLocked`)
- [x] Stop timer on power off (`NSWorkspace.willPowerOffNotification`) — note: OS gives ~8 s; slow networks may not finish in time
- [x] Login item: install app to `/Applications`, reboot, verify it launches at login (requires macOS 13+)
- [x] Resume dialog: on screen unlock or app launch after auto-stop, shows project picker — verify pre-selection, Start Timer, and Dismiss

### Features / improvements
- [x] Handle entries with no project — prompts to assign a project or delete the entry
