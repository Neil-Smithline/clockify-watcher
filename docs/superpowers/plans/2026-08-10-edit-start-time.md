# Edit Start Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `Edit Start Time…` menubar item that lets the user move the running Clockify timer's start time earlier via a modal time picker.

**Architecture:** The date arithmetic and validation live in a new pure function (`resolveStartTime`) so they can be unit-tested without a UI. `AppDelegate` caches the whole running `ClockifyTimeEntry` instead of two derived fields, which supplies the entry id and the description/task/tag values that Clockify's whole-entry `PUT` would otherwise wipe. The dialog itself is an `NSAlert` with an `NSDatePicker` accessory view, matching the app's three existing dialogs.

**Tech Stack:** Swift 5, AppKit, XCTest, hand-maintained `project.pbxproj`. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-10-edit-start-time-design.md`

## Global Constraints

- Pure AppKit / Swift. No SwiftUI, no third-party dependencies.
- Deployment target macOS 11.0; bundle ID `com.clockify.ClockifyWatcher`.
- `project.pbxproj` is maintained **by hand** — Xcode is never used to add files. UUID prefix convention: `AA*` base, `BB*` Keychain, `CC*` Client, `DD*` Formatting, `EE*` reserved for future frameworks. **This plan introduces `FF*` for StartTime.**
- Build: `xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build build`
- Test: `xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test`
- Run one test class: append `-only-testing:ClockifyWatcherTests/<ClassName>`
- All commands run from the repo root, `/Users/neil/Code/clockify-watcher`.
- `billable` stays hardcoded `true` on every create and update (established by commit `bb259dc`).
- Menu item title is exactly `Edit Start Time…` (U+2026 horizontal ellipsis, not three periods).
- Validation rule: the new start must be **no later than the entry's current start**. Equal is allowed.

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `ClockifyWatcher/StartTime.swift` | **create** | `StartTimeError`, `resolveStartTime(picked:currentStart:now:calendar:)` — pure date arithmetic + validation |
| `ClockifyWatcherTests/StartTimeTests.swift` | **create** | Unit tests for the above |
| `ClockifyWatcher/ClockifyClient.swift` | modify | Decode `description`/`taskId`/`tagIds`; rename `updateEntryProject` → `updateEntry` and echo those fields back |
| `ClockifyWatcherTests/ClockifyClientTests.swift` | modify | Decoding tests + a recording session that asserts the PUT body |
| `ClockifyWatcher/AppDelegate.swift` | modify | `activeEntry` state, menu item, `showEditStartTimeDialog` |
| `ClockifyWatcher.xcodeproj/project.pbxproj` | modify | Register the two new files under the `FF*` prefix |
| `CLAUDE.md` | modify | File table, UUID convention, TODO entries |

---

### Task 1: Pure start-time resolution and validation

Builds the testable core first, with nothing depending on it yet. Includes the
`project.pbxproj` wiring, because the test cannot run until both new files are in the
build.

**Files:**
- Create: `ClockifyWatcher/StartTime.swift`
- Create: `ClockifyWatcherTests/StartTimeTests.swift`
- Modify: `ClockifyWatcher.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum StartTimeError: Error, Equatable { case notEarlier }`
  - `func resolveStartTime(picked: Date, currentStart: Date, now: Date, calendar: Calendar = .current) -> Result<Date, StartTimeError>`

  Task 4 calls `resolveStartTime` and switches on the `Result`.

- [ ] **Step 1: Register the new files in `project.pbxproj`**

Five separate edits. Each new line copies the indentation (tabs) of the line above it.

**1a.** In `/* Begin PBXBuildFile section */`, after the `DD0000000000000000000002 /* FormattingTests.swift in Sources */` line, add:

```
		FF0000000000000000000001 /* StartTime.swift in Sources */ = {isa = PBXBuildFile; fileRef = FF0000000000000000000003 /* StartTime.swift */; };
		FF0000000000000000000002 /* StartTimeTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = FF0000000000000000000004 /* StartTimeTests.swift */; };
```

**1b.** In `/* Begin PBXFileReference section */`, after the `DD0000000000000000000004 /* FormattingTests.swift */` line, add:

```
		FF0000000000000000000003 /* StartTime.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StartTime.swift; sourceTree = "<group>"; };
		FF0000000000000000000004 /* StartTimeTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StartTimeTests.swift; sourceTree = "<group>"; };
```

**1c.** In the `AA0000000000000000000602 /* ClockifyWatcher */` PBXGroup, after the `DD0000000000000000000003 /* Formatting.swift */,` line, add:

```
				FF0000000000000000000003 /* StartTime.swift */,
```

**1d.** In the `AA0000000000000000000603 /* ClockifyWatcherTests */` PBXGroup, after the `DD0000000000000000000004 /* FormattingTests.swift */,` line, add:

```
				FF0000000000000000000004 /* StartTimeTests.swift */,
```

**1e.** In `/* Begin PBXSourcesBuildPhase section */`: in `AA0000000000000000000801 /* Sources */` (the app target), after `DD0000000000000000000001 /* Formatting.swift in Sources */,` add:

```
				FF0000000000000000000001 /* StartTime.swift in Sources */,
```

and in `AA0000000000000000000803 /* Sources */` (the test target), after `DD0000000000000000000002 /* FormattingTests.swift in Sources */,` add:

```
				FF0000000000000000000002 /* StartTimeTests.swift in Sources */,
```

- [ ] **Step 2: Write the failing tests**

Create `ClockifyWatcherTests/StartTimeTests.swift`:

```swift
import XCTest
@testable import ClockifyWatcher

final class StartTimeTests: XCTestCase {

    /// Fixed UTC calendar so these tests do not depend on the machine's timezone.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day,
                                      hour: hour, minute: minute, second: second))!
    }

    func testEarlierTimeSucceedsWithSecondsZeroedOnToday() {
        let result = resolveStartTime(picked: date(2026, 8, 10, 9, 15, 30),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(date(2026, 8, 10, 9, 15, 0)))
    }

    func testPickedDateComponentIsIgnoredInFavorOfToday() {
        // The picker can hand back any date; only the clock time is used.
        let result = resolveStartTime(picked: date(1999, 1, 1, 9, 15),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(date(2026, 8, 10, 9, 15, 0)))
    }

    func testEqualToCurrentStartSucceeds() {
        let currentStart = date(2026, 8, 10, 10, 0)
        let result = resolveStartTime(picked: currentStart,
                                      currentStart: currentStart,
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .success(currentStart))
    }

    func testLaterThanCurrentStartFails() {
        let result = resolveStartTime(picked: date(2026, 8, 10, 10, 45),
                                      currentStart: date(2026, 8, 10, 10, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .failure(.notEarlier))
    }

    func testYesterdayStartRejectsEveryTimeToday() {
        // An overnight timer cannot be edited: every time today is later than
        // yesterday's start, so it is rejected rather than losing a day.
        let result = resolveStartTime(picked: date(2026, 8, 10, 9, 15),
                                      currentStart: date(2026, 8, 9, 23, 0),
                                      now: date(2026, 8, 10, 14, 0),
                                      calendar: cal)
        XCTAssertEqual(result, .failure(.notEarlier))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build \
  -only-testing:ClockifyWatcherTests/StartTimeTests test
```

Expected: compile failure — `cannot find 'resolveStartTime' in scope`.

If instead you get "Build input file cannot be found: StartTimeTests.swift", Step 1's
pbxproj edits are wrong; fix those before continuing.

- [ ] **Step 4: Write the implementation**

Create `ClockifyWatcher/StartTime.swift`:

```swift
import Foundation

enum StartTimeError: Error, Equatable {
    /// The chosen time is later than the entry's current start.
    case notEarlier
}

/// Resolves a picked clock time into an absolute start date for the running entry.
///
/// Only the hour and minute of `picked` are used; they are combined with the calendar
/// day of `now` and seconds are zeroed, matching `formatElapsed`'s minute granularity.
///
/// The result must be no later than `currentStart` — the editor can only move a start
/// earlier. Since `currentStart` is always at or before `now`, this also rules out
/// future start times, and it rejects every edit to an entry that began on an earlier
/// day.
func resolveStartTime(picked: Date,
                      currentStart: Date,
                      now: Date,
                      calendar: Calendar = .current) -> Result<Date, StartTimeError> {
    let time = calendar.dateComponents([.hour, .minute], from: picked)
    guard let resolved = calendar.date(bySettingHour: time.hour ?? 0,
                                       minute: time.minute ?? 0,
                                       second: 0,
                                       of: now),
          resolved <= currentStart else {
        return .failure(.notEarlier)
    }
    return .success(resolved)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build \
  -only-testing:ClockifyWatcherTests/StartTimeTests test
```

Expected: `** TEST SUCCEEDED **`, 5 tests passing.

- [ ] **Step 6: Run the full suite to confirm nothing regressed**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add ClockifyWatcher/StartTime.swift ClockifyWatcherTests/StartTimeTests.swift \
        ClockifyWatcher.xcodeproj/project.pbxproj
git commit -m "feat: add resolveStartTime for validating an earlier start time"
```

---

### Task 2: Preserve description, task, and tags across the update

Clockify's `PUT /workspaces/{workspaceId}/time-entries/{id}` replaces the entire entry —
any field omitted from the body is cleared. The model currently decodes only three
fields, so updating an entry silently wipes its description, task, and tags. This task
fixes that, which also repairs the existing no-project flow.

**Files:**
- Modify: `ClockifyWatcher/ClockifyClient.swift:17-21` (`ClockifyTimeEntry`), `:40-44` (`UpdateEntryBody`), `:118-121` (`updateEntryProject`)
- Modify: `ClockifyWatcherTests/ClockifyClientTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `ClockifyTimeEntry` gains `let description: String?`, `let taskId: String?`, `let tagIds: [String]?`
  - `func updateEntry(workspaceId: String, entryId: String, start: Date, projectId: String, description: String?, taskId: String?, tagIds: [String]?) async throws` — replaces `updateEntryProject`

  Tasks 3 and 4 both call `updateEntry`. Task 3 reads the three new model fields.

- [ ] **Step 1: Write the failing tests**

In `ClockifyWatcherTests/ClockifyClientTests.swift`, add these two decoding tests
immediately after `testDecodeTimeEntryWithNullProjectId`:

```swift
    func testDecodeTimeEntryPreservesDescriptionTaskAndTags() throws {
        let json = """
        {
          "id":"entry3",
          "projectId":"proj1",
          "description":"writing docs",
          "taskId":"task1",
          "tagIds":["tag1","tag2"],
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertEqual(entry.description, "writing docs")
        XCTAssertEqual(entry.taskId, "task1")
        XCTAssertEqual(entry.tagIds, ["tag1", "tag2"])
    }

    func testDecodeTimeEntryWithoutOptionalFields() throws {
        // The polling response may omit these keys entirely; decoding must still work.
        let json = """
        {
          "id":"entry4",
          "projectId":"proj1",
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertNil(entry.description)
        XCTAssertNil(entry.taskId)
        XCTAssertNil(entry.tagIds)
    }
```

Then add this networking test at the end of the `ClockifyClientTests` class, after
`testFetchRunningEntryReturnsFirst`:

```swift
    func testUpdateEntrySendsPreservedFieldsAndNoEnd() async throws {
        let session = RecordingURLSession()
        let client = ClockifyClient(apiKey: "key", session: session)

        try await client.updateEntry(workspaceId: "ws1", entryId: "e1",
                                     start: Date(timeIntervalSince1970: 1_700_000_000),
                                     projectId: "p1",
                                     description: "writing docs",
                                     taskId: "task1",
                                     tagIds: ["tag1", "tag2"])

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/workspaces/ws1/time-entries/e1")

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["projectId"] as? String, "p1")
        XCTAssertEqual(body["description"] as? String, "writing docs")
        XCTAssertEqual(body["taskId"] as? String, "task1")
        XCTAssertEqual(body["tagIds"] as? [String], ["tag1", "tag2"])
        XCTAssertEqual(body["billable"] as? Bool, true)
        XCTAssertNotNil(body["start"])
        XCTAssertNil(body["end"], "A running entry must not be given an end time")
    }
```

Finally, add this recording session in the `// MARK: - Test helpers` section at the
bottom of the file, after `MockURLSession`. `MockURLSession` is a struct and cannot
record anything, so this is a separate class:

```swift
/// Captures the last request so tests can assert on method, URL, and body.
final class RecordingURLSession: URLSessionProtocol, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?
    let data: Data
    let statusCode: Int

    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build \
  -only-testing:ClockifyWatcherTests/ClockifyClientTests test
```

Expected: compile failure — `value of type 'ClockifyTimeEntry' has no member 'taskId'`
and `value of type 'ClockifyClient' has no member 'updateEntry'`.

- [ ] **Step 3: Extend the models**

In `ClockifyWatcher/ClockifyClient.swift`, replace `ClockifyTimeEntry`:

```swift
struct ClockifyTimeEntry: Decodable {
    let id: String
    let projectId: String?
    let description: String?
    let taskId: String?
    let tagIds: [String]?
    let timeInterval: ClockifyTimeInterval
}
```

and replace `UpdateEntryBody`:

```swift
struct UpdateEntryBody: Encodable {
    let start: Date
    let projectId: String
    let description: String?
    let taskId: String?
    let tagIds: [String]?
    let billable: Bool = true
}
```

`billable` is a `let` with a default value, so Swift's memberwise initializer excludes
it — the call site does not pass it. `JSONEncoder` omits `nil` optionals, so an entry
with no description sends no `description` key, and `end` is never sent at all.

- [ ] **Step 4: Replace `updateEntryProject` with `updateEntry`**

In the same file, replace the `updateEntryProject` method:

```swift
    func updateEntry(workspaceId: String, entryId: String, start: Date, projectId: String,
                     description: String?, taskId: String?, tagIds: [String]?) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries/\(entryId)")
        try await put(url: url, body: UpdateEntryBody(start: start, projectId: projectId,
                                                      description: description,
                                                      taskId: taskId, tagIds: tagIds))
    }
```

The single caller in `AppDelegate.swift` (inside `showNoProjectDialog`) now fails to
compile. Fix it provisionally so the suite can run — Task 3 revisits this method
properly:

```swift
                try? await client.updateEntry(workspaceId: workspaceId, entryId: entryId,
                                              start: start, projectId: selectedId,
                                              description: nil, taskId: nil, tagIds: nil)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ClockifyWatcher/ClockifyClient.swift ClockifyWatcher/AppDelegate.swift \
        ClockifyWatcherTests/ClockifyClientTests.swift
git commit -m "feat: preserve description, task, and tags when updating a time entry"
```

---

### Task 3: Cache the running entry in `AppDelegate`

`AppDelegate` tracks the running timer with `activeProjectId` and `activeEntryStart`,
neither of which carries the entry id the `PUT` needs, nor the fields Task 2 added.
Collapse both into the entry itself rather than adding more parallel state.

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift:11-12` (properties), `:71-84` (`stopTimerSync`), `:126-161` (`showNoProjectDialog`), `:298-340` (`poll`)

**Interfaces:**
- Consumes: `ClockifyTimeEntry.description` / `.taskId` / `.tagIds` and
  `ClockifyClient.updateEntry(workspaceId:entryId:start:projectId:description:taskId:tagIds:)`
  from Task 2.
- Produces:
  - `var activeEntry: ClockifyTimeEntry?` — the running entry, non-nil only when it has a project
  - `var activeProjectId: String?` — now a computed property
  - `var activeEntryStart: Date?` — now a computed property
  - `private func showNoProjectDialog(entry: ClockifyTimeEntry)` — signature changed from `(entryId:start:)`

  Task 4 reads `activeEntry` to get the entry id and the preserved fields.

There are no new tests here: `AppDelegate` has no test coverage in this project, and
the refactor is behavior-preserving. The gate is that the build succeeds and the
existing suite still passes.

- [ ] **Step 1: Replace the two stored properties with the cached entry**

In `ClockifyWatcher/AppDelegate.swift`, replace these two lines:

```swift
    var activeProjectId: String?
    var activeEntryStart: Date?
```

with:

```swift
    /// The running entry, cached from the last poll. Non-nil only when it has a project.
    var activeEntry: ClockifyTimeEntry?
    var activeProjectId: String? { activeEntry?.projectId }
    var activeEntryStart: Date? { activeEntry?.timeInterval.start }
```

- [ ] **Step 2: Update the two assignment sites**

In `stopTimerSync`, replace:

```swift
        DispatchQueue.main.async {
            self.activeProjectId = nil
            self.activeEntryStart = nil
            self.updateStatusItem()
        }
```

with:

```swift
        DispatchQueue.main.async {
            self.activeEntry = nil
            self.updateStatusItem()
        }
```

In `poll`, replace the whole `if let entry { ... } else { ... }` block with:

```swift
                    if let entry {
                        if let projectId = entry.projectId {
                            self.activeEntry = entry
                            self.noProjectEntryId = nil
                            if self.cachedProjects[projectId] == nil {
                                Task { await self.refreshProjects() }
                            }
                        } else if entry.id != self.noProjectEntryId {
                            self.activeEntry = nil
                            self.noProjectEntryId = entry.id
                            self.showNoProjectDialog(entry: entry)
                        }
                    } else {
                        self.activeEntry = nil
                        self.noProjectEntryId = nil
                    }
```

Note the `else if` branch no longer clears `activeEntry` twice, and the third branch
drops the now-nonexistent `activeEntryStart = nil`.

- [ ] **Step 3: Make the no-project dialog preserve the entry's fields**

Change the signature and body of `showNoProjectDialog`. Replace:

```swift
    private func showNoProjectDialog(entryId: String, start: Date) {
```

with:

```swift
    private func showNoProjectDialog(entry: ClockifyTimeEntry) {
        let entryId = entry.id
```

and replace the provisional call added in Task 2 with one that echoes the real values:

```swift
                try? await client.updateEntry(workspaceId: workspaceId, entryId: entryId,
                                              start: entry.timeInterval.start,
                                              projectId: selectedId,
                                              description: entry.description,
                                              taskId: entry.taskId, tagIds: entry.tagIds)
```

The `start:` argument replaces the removed `start` parameter, so the old
`start: start` no longer compiles — that is the intended change.

- [ ] **Step 4: Build and run the full suite**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test
```

Expected: `** TEST SUCCEEDED **`. If the compiler reports "cannot assign to property:
'activeProjectId' is a get-only property", a write site was missed in Step 2 — find it
with `grep -n "activeProjectId =\|activeEntryStart =" ClockifyWatcher/AppDelegate.swift`
and convert it to assign `activeEntry` instead.

- [ ] **Step 5: Commit**

```bash
git add ClockifyWatcher/AppDelegate.swift
git commit -m "refactor: cache the running time entry instead of two derived fields"
```

---

### Task 4: The menu item and the edit dialog

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift` — `populateMenu`, plus two new methods
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `resolveStartTime(picked:currentStart:now:calendar:)` and `StartTimeError`
  from Task 1; `ClockifyClient.updateEntry(...)` from Task 2; `activeEntry` from Task 3.
- Produces: nothing further depends on this task.

As in Task 3, the deliverable is UI code with no automated coverage. The gate is a
clean build, a green suite, and the manual check in Step 5.

- [ ] **Step 1: Add the menu item**

In `populateMenu`, replace the `if activeProjectId != nil { ... }` block with:

```swift
        if activeProjectId != nil {
            let editItem = NSMenuItem(title: "Edit Start Time…",
                                      action: #selector(editStartTime),
                                      keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            let stopItem = NSMenuItem(title: "Stop Timer",
                                      action: #selector(stopTimer),
                                      keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }
```

Then add the action method immediately above `@objc func stopTimer()`:

```swift
    @objc func editStartTime() {
        showEditStartTimeDialog()
    }
```

- [ ] **Step 2: Add the dialog**

Add this method to the `// MARK: - Resume dialog` section, immediately after
`showNoProjectDialog`:

```swift
    /// Shows the start-time editor for the running entry.
    /// - Parameters:
    ///   - error: message text for a re-show after a rejected value; `nil` on first open.
    ///   - prefill: the rejected value to restore into the picker; `nil` uses the current start.
    private func showEditStartTimeDialog(error: String? = nil, prefill: Date? = nil) {
        guard let entry = activeEntry,
              let projectId = entry.projectId,
              let client, let workspaceId else { return }
        let currentStart = entry.timeInterval.start

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let currentStartText = formatter.string(from: currentStart)

        let alert = NSAlert()
        if let error {
            alert.messageText = error
            alert.informativeText =
                "The timer started at \(currentStartText). Pick a time at or before that."
        } else {
            alert.messageText = "Edit start time"
            let projectName = cachedProjects[projectId]?.name ?? "Timer"
            alert.informativeText = "\(projectName) — started \(currentStartText)"
        }
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = prefill ?? currentStart
        alert.accessoryView = picker
        alert.window.initialFirstResponder = picker

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch resolveStartTime(picked: picker.dateValue, currentStart: currentStart, now: Date()) {
        case .failure:
            showEditStartTimeDialog(error: "Start time can only be moved earlier",
                                    prefill: picker.dateValue)
        case .success(let newStart):
            Task {
                do {
                    try await client.updateEntry(workspaceId: workspaceId, entryId: entry.id,
                                                 start: newStart, projectId: projectId,
                                                 description: entry.description,
                                                 taskId: entry.taskId, tagIds: entry.tagIds)
                    poll()
                } catch {
                    await MainActor.run {
                        let failure = NSAlert()
                        failure.messageText = "Failed to update start time"
                        failure.informativeText = error.localizedDescription
                        failure.runModal()
                    }
                }
            }
        }
    }
```

`Save` is added first, so it is the default button and responds to `Return`; `Cancel`
is second and picks up `Escape`. This matches the button ordering in
`showNoProjectDialog` and `promptForApiKey`.

- [ ] **Step 3: Build and run the full suite**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Update `CLAUDE.md`**

Add a row to the file table, after the `Formatting.swift` row:

```markdown
| `StartTime.swift` | `resolveStartTime(picked:currentStart:now:calendar:)` — start-time edit validation |
```

Replace the UUID convention bullet with:

```markdown
- Xcode project file (`project.pbxproj`) is maintained by hand; UUID prefix convention: `AA*` base, `BB*` Keychain, `CC*` Client, `DD*` Formatting, `EE*` future frameworks, `FF*` StartTime
```

Under `### Needs manual testing`, add:

```markdown
- [ ] Edit Start Time dialog: pre-fill, saving an earlier time, rejection of a later time, Cancel
```

Under `### Features / improvements`, add:

```markdown
- [x] Edit the start time of the running timer — moves the start earlier only; rejects later times and overnight entries
```

- [ ] **Step 5: Manual check**

```bash
xcodebuild -scheme ClockifyWatcher -configuration Debug -derivedDataPath /tmp/cw-build build
open /tmp/cw-build/Build/Products/Debug/ClockifyWatcher.app
```

With a timer running, open the menubar menu and confirm:

1. `Edit Start Time…` appears directly above `Stop Timer`.
2. It opens a dialog pre-filled with the current start time, titled with the project name.
3. Picking a time 20 minutes earlier and pressing `Return` makes the menubar elapsed time jump forward by ~20 minutes.
4. Re-opening it and picking a *later* time re-shows the dialog with
   "Start time can only be moved earlier" and the rejected value still in the field.
5. `Escape` closes the dialog and changes nothing.
6. With no timer running, the menu shows neither `Edit Start Time…` nor `Stop Timer`.

Quit the app when done.

- [ ] **Step 6: Commit**

```bash
git add ClockifyWatcher/AppDelegate.swift CLAUDE.md
git commit -m "feat: add Edit Start Time dialog for the running timer"
```
