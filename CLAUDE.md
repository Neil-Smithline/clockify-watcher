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
| `StartTime.swift` | `resolveStartTime(picked:currentStart:now:calendar:)` — start-time edit validation |
| `PollSchedule.swift` | Poll interval, rate-limit backoff (`nextPollDelay`), API-budget constants |
| `Log.swift` | `os_log` channels (`Log.api`, `Log.poll`) |

Key decisions:
- **API budget:** Clockify's Free plan allows **30 requests/hour per workspace**. Exceeding it returns 429 on every data endpoint (`/user` keeps working) until the window rolls over, which presents as the app silently losing API access. Everything in `PollSchedule.swift` is sized around this budget; re-check it before adding any new request.
- Polling: 180 s for API state (20 requests/hour), 1 s display timer for elapsed-time tick. The display timer computes elapsed time locally from the cached start, so the menubar clock ticks smoothly no matter how slow the poll is
- Each poll schedules the next one (`schedulePoll`) rather than using a repeating timer, so a 429 can back off: 5 → 10 → 20 → 40 → 60 min, capped at the hourly window, honouring `Retry-After` when present
- `menuWillOpen` refreshes state only when the last poll is older than `menuPollStaleness`, and never during a backoff — menu opens are unbounded and each one used to cost two requests
- A failed project fetch is held off for `projectsRetryCooldown`; retrying it on every poll doubled the request rate exactly when over quota
- Menu is rebuilt synchronously in `menuWillOpen` (not on a timer)
- `stopTimerSync` bridges async → sync via `DispatchSemaphore` for notification handlers that must return before the OS proceeds (sleep, lock, power-off)
- `SMAppService.mainApp.register()` is called every launch — it is idempotent and only takes effect when the app runs from `/Applications`
- Xcode project file (`project.pbxproj`) is maintained by hand; UUID prefix convention: `AA*` base, `BB*` Keychain, `CC*` Client, `DD*` Formatting, `EE*` future frameworks, `FF*` StartTime, `GG*` Log, `HH*` PollSchedule
- Bundle ID: `com.clockify.ClockifyWatcher`, deployment target: macOS 11.0

## Debugging

The app has no UI for errors beyond the menubar, so API failures go to the unified log:

```bash
log stream --predicate 'subsystem == "com.clockify.ClockifyWatcher"'
log show --last 1h --predicate 'subsystem == "com.clockify.ClockifyWatcher"' --style compact
```

Raw HTTP traffic (status codes, timings) is visible even without app logging:

```bash
log show --last 1h --predicate 'process == "ClockifyWatcher" AND subsystem == "com.apple.CFNetwork"' --style compact | grep "summary for task"
```

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
- [ ] Rate limiting: force a 429 (burn 30 requests in an hour), then verify the menu shows "Rate limited by Clockify — retrying HH:mm", the backoff grows instead of polling every 3 min, and a success clears it
- [ ] Edit Start Time dialog: pre-fill, saving an earlier time, rejection of a later time, Cancel, and — lock the screen while the dialog is open, unlock, then click Save: the save must be refused with the "Timer is no longer running" alert rather than restarting the stopped timer

### Features / improvements
- [x] Handle entries with no project — prompts to assign a project or delete the entry
- [x] Edit the start time of the running timer — moves the start earlier only; rejects later times and overnight entries
