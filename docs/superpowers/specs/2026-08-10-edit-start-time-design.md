# Edit Start Time — Design

**Date:** 2026-08-10
**Status:** Approved

## Goal

Let the user correct the start time of the currently running Clockify timer from the
menubar menu. In practice this means "I forgot to start the timer 20 minutes ago" —
the edit can only move the start *earlier*, never later.

## User-facing behavior

A new menu item, `Edit Start Time…`, sits immediately above `Stop Timer` and appears
under the same condition (a timer with a project is running). Selecting it opens a
modal dialog:

```
┌─────────────────────────────────────────┐
│  Edit start time                        │
│  Project B — started 9:30 AM            │
│                                         │
│  Timer started at:  [ 9:30 AM ⌄ ]       │
│                                         │
│              [ Cancel ]  [ Save ]       │
└─────────────────────────────────────────┘
```

- The field is an absolute clock time, pre-filled with the entry's current start.
- Hour and minute only — matching `formatElapsed`, which renders `H:MM`. Seconds are
  zeroed on save.
- The date component is always **today**; there is no date field.
- `Save` is the default button (`Return`); `Cancel` is `Escape` and changes nothing.

### Validation

The chosen time must be **no later than the entry's current start**. Equal is allowed
and saves a no-op.

Because the current start is always at or before now, this single rule also rules out
future start times.

It also resolves the overnight case: an entry that started yesterday cannot be edited
at all, since every time today is later than it. The edit is rejected rather than
silently pulling the entry forward a day and losing the elapsed time.

`NSDatePicker` has no built-in "earlier only" constraint that spans midnight, so this
is a check at Save time, not a `maxDate` on the control. A later time can be typed; it
just cannot be saved.

On rejection the dialog re-opens with the rejected value still in the picker:

```
┌─────────────────────────────────────────────────┐
│  Start time can only be moved earlier           │
│  The timer started at 9:30 AM. Pick a time      │
│  at or before that.                             │
│                                                 │
│  Timer started at:  [ 9:45 AM ⌄ ]               │
│                                                 │
│                      [ Cancel ]  [ Save ]       │
└─────────────────────────────────────────────────┘
```

On API failure, an alert titled `Failed to update start time` shows
`error.localizedDescription`, matching `stopTimer` and `switchProject`. The dialog does
not reopen.

## Implementation

### Client layer (`ClockifyClient.swift`)

Clockify's `PUT /workspaces/{workspaceId}/time-entries/{id}` replaces the whole entry —
omitted fields are cleared. `ClockifyTimeEntry` currently decodes only `id`,
`projectId`, and `timeInterval`, so a naive save would wipe description, task, and
tags. The model gains those fields:

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

`UpdateEntryBody` gains the same three, all optional. `JSONEncoder` omits nils, so
`end` stays absent and the entry keeps running.

`updateEntryProject(...)` is renamed to:

```swift
func updateEntry(workspaceId: String, entryId: String, start: Date,
                 projectId: String, description: String?,
                 taskId: String?, tagIds: [String]?) async throws
```

One method serves both the new edit-start flow and the existing no-project flow. As a
side effect the no-project flow stops wiping description/task/tags, which it does
today.

`billable` stays hardcoded `true`, per commit `bb259dc`.

### State (`AppDelegate.swift`)

Three fields currently track the running entry (`activeProjectId`, `activeEntryStart`,
`noProjectEntryId`) and none holds the entry id for the normal case, which the PUT
needs. Rather than add a fourth, collapse the first two into the entry:

```swift
var activeEntry: ClockifyTimeEntry?          // set only when the entry has a project
var activeProjectId: String? { activeEntry?.projectId }
var activeEntryStart: Date?  { activeEntry?.timeInterval.start }
```

`poll()` assigns `activeEntry = entry` in the has-project branch and `nil` in the other
two; `stopTimerSync()` sets it to `nil`. Every reader of `activeProjectId` /
`activeEntryStart` — status item, checkmarks, menu building, `switchProject` — is
unchanged.

`noProjectEntryId` stays as-is; it tracks a different thing (a dialog already shown for
a project-less entry).

This hands the edit action the entry id plus description/task/tags with no extra fetch.
The data is at most one `menuWillOpen` poll old.

### Dialog

`showEditStartTimeDialog(error:)` follows the pattern of `showNoProjectDialog`: an
`NSAlert` with an `NSDatePicker` accessory view (`.textFieldAndStepper`,
`.hourMinute`). The `error:` parameter drives the recursive re-show on validation
failure, exactly as `promptForApiKey(error:)` already does.

### Testable seam (`StartTime.swift`)

The date arithmetic and the guard do not belong inside a modal-dialog method. They move
into one pure function in a new file:

```swift
enum StartTimeError: Error { case notEarlier }

/// Combines today's date with the picked clock time, then validates it
/// against the entry's current start.
func resolveStartTime(picked: Date, currentStart: Date,
                      now: Date, calendar: Calendar = .current) -> Result<Date, StartTimeError>
```

`now` and `calendar` are injected so tests depend on neither the wall clock nor the
machine's timezone.

The dialog method reduces to: read picker → call this → on `.success` fire the PUT, on
`.failure` re-show with the error.

### Menu

In `populateMenu`, inside the existing `if activeProjectId != nil` block, add
`Edit Start Time…` immediately above `Stop Timer`.

## Testing

**`ClockifyClientTests`**

- decode an entry carrying `description` / `taskId` / `tagIds`
- decode an entry where all three are absent → nil (guards against a decoding
  regression breaking the existing poll)
- `updateEntry` issues `PUT` to `.../time-entries/{id}` with `start`, `projectId`, and
  the three preserved fields in the body, and no `end` key

**`StartTimeTests`** (new)

- picked earlier than current start → `.success`, seconds zeroed, today's date
- picked equal to current start → `.success`
- picked later than current start → `.failure(.notEarlier)`
- current start was yesterday, any time today → `.failure(.notEarlier)`

The dialog and the menu item stay untested, consistent with the rest of `AppDelegate`;
covering them would need UI-test scaffolding the project does not have.

## Documentation

`CLAUDE.md` gains `- [x] Edit the start time of the running timer` under
Features / improvements, and a manual-testing entry for the dialog.

## Out of scope

- Editing the end time, or editing stopped entries
- Editing the start time of a project-less entry (the existing no-project dialog owns
  that case)
- Changing the date of an entry
- Relative-offset input (`-15m`) or preset nudge buttons
