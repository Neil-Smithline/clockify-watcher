# Clockify Menubar App — Design Spec

**Date:** 2026-04-24  
**Status:** Approved

---

## Overview

A macOS menubar app that displays the currently running Clockify timer — project name and elapsed time — in the project's color. Provides quick project-switching, and links to the Clockify desktop app and browser.

---

## Stack

- **Language:** Swift
- **Framework:** Pure AppKit (no SwiftUI)
- **Project type:** Xcode app bundle
- **Minimum macOS:** 11.0 (Big Sur)
- **`LSUIElement = YES`** in Info.plist — hides from Dock and App Switcher entirely

---

## File Structure

```
clockify-watcher/
├── clockify-watcher.xcodeproj
└── clockify-watcher/
    ├── main.swift
    ├── AppDelegate.swift
    ├── ClockifyClient.swift
    ├── KeychainHelper.swift
    ├── Info.plist
    └── Assets.xcassets/
        └── clockify-logo.imageset/   # template image, dark/light adaptive
```

### Responsibilities

| File | Responsibility |
|------|----------------|
| `AppDelegate.swift` | Owns `NSStatusItem`, drives the 30s timer, updates UI, builds and owns the menu |
| `ClockifyClient.swift` | All API calls — typed Swift structs, `async/await` with `URLSession` |
| `KeychainHelper.swift` | Read/write API key from macOS Keychain |
| `Assets.xcassets` | Clockify logo as a template image (auto-adapts to dark/light mode) |

---

## Menubar Display

### When a timer is running

```
[⧗] *1:23 ProjectName
```

- `[⧗]` — Clockify template image (white in dark mode, black in light mode via `isTemplate = true`)
- `*1:23` — elapsed time in `H:MM` format; `*` prefix appears after 2 consecutive poll failures
- `ProjectName` — name of the active project
- Time and project name rendered as `NSAttributedString` in the project's hex color

### When no timer is running

```
[⧗]
```

- Clockify template image only, no text

### Stale data indicator

After **2 consecutive failed polls** (~1 minute), prefix the time with `*` (e.g. `*1:23 ProjectName`) in the same project color. Cleared immediately on the next successful poll. When no timer is running and polls are failing, append `*` as a text suffix to the icon area.

---

## Menu Structure

Rebuilt from scratch each time the menu opens.

```
 ✓  ProjectAlpha          ← checkmark on currently active project
    ProjectBeta
    ProjectGamma
─────────────────
    Open Clockify App
    Open in Browser
─────────────────
    Quit
```

- Projects sorted alphabetically, all non-archived projects shown
- Checkmark on whichever project has the active timer (none if no timer running)
- Opening the menu shows the cached project list immediately, then triggers a background refresh (non-blocking); updated list appears on next open

---

## Data Flow

### Launch sequence

1. Check Keychain for API key
   - If absent → show first-run setup (see below)
2. `GET /v1/user` → cache `userId` and `workspaceId` for the session
3. `GET /v1/workspaces/{workspaceId}/projects?archived=false` → cache project list (name + color, keyed by `projectId`)
4. Run first poll immediately, then start 30s repeating timer

### Poll (every 30 seconds)

1. `GET /v1/workspaces/{workspaceId}/user/{userId}/time-entries?in-progress=true&limit=1`
2. If no running entry → display icon only
3. If running entry → look up `projectId` in project cache
   - If found → render `[icon] H:MM ProjectName` in project color
   - If not found → trigger project list refresh, then re-render; if still unknown, render `[icon] H:MM` in system color
4. On success, reset consecutive-failure counter; on failure, increment it

### Switch project (user taps a project in menu)

If the tapped project is already the active one (checkmarked), do nothing.

Otherwise:
1. `PATCH /v1/workspaces/{workspaceId}/user/{userId}/time-entries` — stop current timer (send current UTC time as end); skip if no timer running
2. `POST /v1/workspaces/{workspaceId}/time-entries` — start new timer with selected `projectId`, no description
3. Trigger immediate poll to refresh display

---

## Project List Caching

No time-based refresh. The cache is invalidated and re-fetched in exactly two situations:

1. **User opens the dropdown menu** — trigger a background refresh (non-blocking; updated list visible on next open)
2. **Poll returns an unknown `projectId`** — fetch immediately and re-render

This is sufficient because projects change infrequently, and these two triggers cover all cases where stale data would be visible or incorrect.

---

## First-Run Setup

On launch, if no API key exists in Keychain:

1. Show an `NSAlert` with a text field asking for the Clockify API key (found in Clockify → Profile Settings → API)
2. On confirm, call `GET /v1/user` to validate the key
   - On 401 → show error message, re-prompt
   - On success → save to Keychain, proceed with launch sequence

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| Network error during poll | Silent — increment failure counter, retry next tick. No alert. |
| 2+ consecutive poll failures | Prefix time with `*` (stale indicator) |
| 401 Unauthorized (any call) | Clear Keychain entry, re-show API key prompt |
| Unknown `projectId` after cache refresh | Display `[icon] H:MM` in system color (no project name) |
| Switch project API failure | Show `NSAlert` — explicit user action, silent failure would be confusing |
| Clockify desktop app not installed | "Open Clockify App" falls back to opening the browser |

**No unsolicited modal dialogs for background errors.** The app must never interrupt the user with unexpected alerts during normal operation.

---

## API Endpoints Used

All requests include `X-Api-Key: <stored key>` header.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/v1/user` | Get `userId`, `activeWorkspace` |
| `GET` | `/v1/workspaces/{wid}/projects?archived=false` | List all active projects |
| `GET` | `/v1/workspaces/{wid}/user/{uid}/time-entries?in-progress=true&limit=1` | Current running timer |
| `PATCH` | `/v1/workspaces/{wid}/user/{uid}/time-entries` | Stop current timer |
| `POST` | `/v1/workspaces/{wid}/time-entries` | Start new timer |

---

## Keychain Storage

- **Service:** `clockify-watcher`
- **Account:** `api-key`
- Uses `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
- Key is never written to disk outside the Keychain

---

## Out of Scope

- Task-level tracking (project only)
- Multiple workspace support
- Timer descriptions
- Starting/stopping timers other than via project switch
- Preferences UI beyond API key setup
