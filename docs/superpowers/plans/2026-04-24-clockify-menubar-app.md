# ClockifyWatcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure AppKit macOS menubar app that displays the current Clockify timer with colored project text and supports project switching.

**Architecture:** NSStatusItem with NSAttributedString for colored text, 30-second polling timer, in-memory project cache, async/await networking via URLSession with a testable protocol, Keychain for API key storage.

**Tech Stack:** Swift 5.9+, AppKit, Foundation (URLSession, JSONDecoder), Security framework (Keychain), XCTest, Xcode 15+, macOS 11+ deployment target.

---

## File Map

| File | Status | Purpose |
|------|--------|---------|
| `ClockifyWatcher/main.swift` | Create | App entry point — NSApplication setup |
| `ClockifyWatcher/AppDelegate.swift` | Create | NSStatusItem, menu, timer, all UI logic |
| `ClockifyWatcher/ClockifyClient.swift` | Create | Response models + all API calls via URLSession |
| `ClockifyWatcher/KeychainHelper.swift` | Create | API key save/load/delete via Security framework |
| `ClockifyWatcher/Formatting.swift` | Create | Elapsed time H:MM formatter + NSColor hex init |
| `ClockifyWatcher/Info.plist` | Modify | LSUIElement=YES, remove storyboard key |
| `ClockifyWatcher/Assets.xcassets` | Modify | Add clockify-logo as template image |
| `ClockifyWatcherTests/KeychainHelperTests.swift` | Create | Unit tests for Keychain |
| `ClockifyWatcherTests/ClockifyClientTests.swift` | Create | Unit tests for models + API calls |
| `ClockifyWatcherTests/FormattingTests.swift` | Create | Unit tests for elapsed time + hex color |

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `ClockifyWatcher.xcodeproj` (via Xcode GUI)
- Modify: `ClockifyWatcher/Info.plist`
- Create: `ClockifyWatcher/main.swift`
- Modify: `ClockifyWatcher/AppDelegate.swift`

- [ ] **Step 1: Create new Xcode project**

  In Xcode: File → New → Project → macOS → App
  - Product Name: `ClockifyWatcher`
  - Bundle Identifier: `com.yourname.clockify-watcher`
  - Language: Swift
  - Uncheck "Use Core Data", uncheck "Include SwiftUI"
  - Check "Include Tests"
  - Save to `~/Code/clockify-watcher/` (Xcode creates the subdirectory)

- [ ] **Step 2: Delete default boilerplate files**

  In Xcode's Project Navigator, delete (Move to Trash):
  - `ClockifyWatcher/ViewController.swift`
  - `ClockifyWatcher/Main.storyboard`
  - `ClockifyWatcher/ContentView.swift` (if present)

- [ ] **Step 3: Configure Info.plist**

  Open `ClockifyWatcher/Info.plist` (right-click → Open As → Source Code) and ensure it contains:
  ```xml
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  ```
  Delete the `NSMainStoryboardFile` key if present:
  ```xml
  <!-- DELETE this key/value pair if it exists: -->
  <key>NSMainStoryboardFile</key>
  <string>Main</string>
  ```

- [ ] **Step 4: Replace AppDelegate.swift**

  Replace entire content of `ClockifyWatcher/AppDelegate.swift`:
  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      func applicationDidFinishLaunching(_ notification: Notification) {
          // Populated in later tasks
      }
  }
  ```

- [ ] **Step 5: Create main.swift**

  Create `ClockifyWatcher/main.swift`:
  ```swift
  import AppKit

  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()
  ```

  > Note: You cannot have both `@main`/`@NSApplicationMain` on AppDelegate AND a `main.swift`. If Xcode generated `@main` on AppDelegate, remove it now.

- [ ] **Step 6: Build to verify**

  Product → Build (⌘B). Expected: **Build Succeeded**. No icon appears yet — that's correct.

- [ ] **Step 7: Commit**

  ```bash
  cd ~/Code/clockify-watcher
  git add ClockifyWatcher.xcodeproj ClockifyWatcher ClockifyWatcherTests
  git commit -m "feat: create Xcode project skeleton"
  ```

---

## Task 2: KeychainHelper

**Files:**
- Create: `ClockifyWatcher/KeychainHelper.swift`
- Create: `ClockifyWatcherTests/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

  Create `ClockifyWatcherTests/KeychainHelperTests.swift`:
  ```swift
  import XCTest
  @testable import ClockifyWatcher

  final class KeychainHelperTests: XCTestCase {
      let testService = "clockify-watcher-test"
      let testAccount = "api-key"

      override func tearDown() {
          KeychainHelper.delete(service: testService, account: testAccount)
      }

      func testSaveAndLoad() {
          KeychainHelper.save("test-api-key-123", service: testService, account: testAccount)
          let loaded = KeychainHelper.load(service: testService, account: testAccount)
          XCTAssertEqual(loaded, "test-api-key-123")
      }

      func testLoadReturnsNilWhenAbsent() {
          let loaded = KeychainHelper.load(service: testService, account: testAccount)
          XCTAssertNil(loaded)
      }

      func testOverwrite() {
          KeychainHelper.save("first-key", service: testService, account: testAccount)
          KeychainHelper.save("second-key", service: testService, account: testAccount)
          let loaded = KeychainHelper.load(service: testService, account: testAccount)
          XCTAssertEqual(loaded, "second-key")
      }

      func testDelete() {
          KeychainHelper.save("test-key", service: testService, account: testAccount)
          KeychainHelper.delete(service: testService, account: testAccount)
          let loaded = KeychainHelper.load(service: testService, account: testAccount)
          XCTAssertNil(loaded)
      }
  }
  ```

- [ ] **Step 2: Run tests — verify they fail**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED)"
  ```
  Expected: compile error — `KeychainHelper` not defined.

- [ ] **Step 3: Implement KeychainHelper**

  Create `ClockifyWatcher/KeychainHelper.swift`:
  ```swift
  import Foundation
  import Security

  enum KeychainHelper {
      static func save(_ value: String, service: String, account: String) {
          let data = Data(value.utf8)
          delete(service: service, account: account)  // allow overwrite
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account,
              kSecValueData: data
          ]
          SecItemAdd(query as CFDictionary, nil)
      }

      static func load(service: String, account: String) -> String? {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account,
              kSecReturnData: true,
              kSecMatchLimit: kSecMatchLimitOne
          ]
          var result: AnyObject?
          guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let data = result as? Data else { return nil }
          return String(data: data, encoding: .utf8)
      }

      static func delete(service: String, account: String) {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account
          ]
          SecItemDelete(query as CFDictionary)
      }

      // App-level convenience
      static func saveApiKey(_ key: String) {
          save(key, service: "clockify-watcher", account: "api-key")
      }

      static func loadApiKey() -> String? {
          load(service: "clockify-watcher", account: "api-key")
      }

      static func deleteApiKey() {
          delete(service: "clockify-watcher", account: "api-key")
      }
  }
  ```

- [ ] **Step 4: Run tests — verify they pass**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED|Test Suite)"
  ```
  Expected: 4 tests pass (`testSaveAndLoad`, `testLoadReturnsNilWhenAbsent`, `testOverwrite`, `testDelete`).

- [ ] **Step 5: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/KeychainHelper.swift ClockifyWatcherTests/KeychainHelperTests.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add KeychainHelper for API key storage"
  ```

---

## Task 3: Clockify Response Models

**Files:**
- Create: `ClockifyWatcher/ClockifyClient.swift` (models only — networking added in Task 4)
- Create: `ClockifyWatcherTests/ClockifyClientTests.swift`

- [ ] **Step 1: Write failing model decode tests**

  Create `ClockifyWatcherTests/ClockifyClientTests.swift`:
  ```swift
  import XCTest
  @testable import ClockifyWatcher

  final class ClockifyClientTests: XCTestCase {

      // MARK: - Model decoding

      func testDecodeUser() throws {
          let json = #"{"id":"user123","activeWorkspace":"ws456","email":"a@b.com","name":"Alice"}"#
              .data(using: .utf8)!
          let user = try JSONDecoder().decode(ClockifyUser.self, from: json)
          XCTAssertEqual(user.id, "user123")
          XCTAssertEqual(user.activeWorkspace, "ws456")
      }

      func testDecodeProject() throws {
          let json = #"{"id":"proj1","name":"My Project","color":"#FF5722","archived":false}"#
              .data(using: .utf8)!
          let project = try JSONDecoder().decode(ClockifyProject.self, from: json)
          XCTAssertEqual(project.id, "proj1")
          XCTAssertEqual(project.name, "My Project")
          XCTAssertEqual(project.color, "#FF5722")
          XCTAssertFalse(project.archived)
      }

      func testDecodeRunningTimeEntry() throws {
          let json = """
          {
            "id":"entry1",
            "projectId":"proj1",
            "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
          }
          """.data(using: .utf8)!
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .iso8601
          let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
          XCTAssertEqual(entry.id, "entry1")
          XCTAssertEqual(entry.projectId, "proj1")
          XCTAssertNil(entry.timeInterval.end)
      }

      func testDecodeTimeEntryWithNullProjectId() throws {
          let json = """
          {
            "id":"entry2",
            "projectId":null,
            "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
          }
          """.data(using: .utf8)!
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .iso8601
          let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
          XCTAssertNil(entry.projectId)
      }
  }
  ```

- [ ] **Step 2: Run tests — verify they fail**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED)"
  ```
  Expected: compile error — `ClockifyUser`, `ClockifyProject`, `ClockifyTimeEntry` not defined.

- [ ] **Step 3: Create ClockifyClient.swift with models**

  Create `ClockifyWatcher/ClockifyClient.swift`:
  ```swift
  import Foundation

  // MARK: - Response models

  struct ClockifyUser: Decodable {
      let id: String
      let activeWorkspace: String
  }

  struct ClockifyProject: Decodable {
      let id: String
      let name: String
      let color: String
      let archived: Bool
  }

  struct ClockifyTimeEntry: Decodable {
      let id: String
      let projectId: String?
      let timeInterval: ClockifyTimeInterval
  }

  struct ClockifyTimeInterval: Decodable {
      let start: Date
      let end: Date?
  }

  // MARK: - Request bodies

  struct StopTimerBody: Encodable {
      let end: Date
  }

  struct StartTimerBody: Encodable {
      let start: Date
      let projectId: String
  }
  ```

- [ ] **Step 4: Run tests — verify they pass**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED|Test Suite)"
  ```
  Expected: 4 model decode tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/ClockifyClient.swift ClockifyWatcherTests/ClockifyClientTests.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add Clockify response models"
  ```

---

## Task 4: ClockifyClient — Networking

**Files:**
- Modify: `ClockifyWatcher/ClockifyClient.swift`
- Modify: `ClockifyWatcherTests/ClockifyClientTests.swift`

- [ ] **Step 1: Add networking tests**

  Append inside the `ClockifyClientTests` class (before the final `}`):
  ```swift
      // MARK: - Networking

      func testFetchUserSuccess() async throws {
          let json = #"{"id":"user123","activeWorkspace":"ws456","email":"a@b.com","name":"Alice"}"#
              .data(using: .utf8)!
          let client = ClockifyClient(apiKey: "test-key", session: MockURLSession(data: json, statusCode: 200))
          let user = try await client.fetchUser()
          XCTAssertEqual(user.id, "user123")
      }

      func testFetchUserThrowsOn401() async {
          let client = ClockifyClient(apiKey: "bad-key", session: MockURLSession(data: Data(), statusCode: 401))
          do {
              _ = try await client.fetchUser()
              XCTFail("Expected ClockifyError.unauthorized")
          } catch ClockifyError.unauthorized {
              // expected
          } catch {
              XCTFail("Wrong error type: \(error)")
          }
      }

      func testFetchProjectsReturnsSortedByName() async throws {
          let json = """
          [
            {"id":"p1","name":"Zebra","color":"#FF0000","archived":false},
            {"id":"p2","name":"Alpha","color":"#00FF00","archived":false}
          ]
          """.data(using: .utf8)!
          let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: json, statusCode: 200))
          let projects = try await client.fetchProjects(workspaceId: "ws1")
          XCTAssertEqual(projects.count, 2)
          XCTAssertEqual(projects[0].name, "Zebra")  // API order preserved; sorting is AppDelegate's job
      }

      func testFetchRunningEntryNilWhenNoTimer() async throws {
          let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: "[]".data(using: .utf8)!, statusCode: 200))
          let entry = try await client.fetchRunningEntry(workspaceId: "ws1", userId: "u1")
          XCTAssertNil(entry)
      }

      func testFetchRunningEntryReturnsFirst() async throws {
          let json = """
          [{"id":"e1","projectId":"p1","timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}}]
          """.data(using: .utf8)!
          let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: json, statusCode: 200))
          let entry = try await client.fetchRunningEntry(workspaceId: "ws1", userId: "u1")
          XCTAssertEqual(entry?.id, "e1")
          XCTAssertEqual(entry?.projectId, "p1")
      }
  ```

  Append after the closing `}` of the class:
  ```swift
  // MARK: - Test helpers

  struct MockURLSession: URLSessionProtocol {
      let data: Data
      let statusCode: Int

      func data(for request: URLRequest) async throws -> (Data, URLResponse) {
          let url = request.url ?? URL(string: "https://example.com")!
          let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                         httpVersion: nil, headerFields: nil)!
          return (data, response)
      }
  }
  ```

- [ ] **Step 2: Run tests — verify they fail**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED)"
  ```
  Expected: compile errors — `URLSessionProtocol`, `ClockifyError`, `ClockifyClient(apiKey:session:)` not defined.

- [ ] **Step 3: Add networking to ClockifyClient.swift**

  Append to `ClockifyWatcher/ClockifyClient.swift` after the existing structs:
  ```swift
  // MARK: - Errors

  enum ClockifyError: Error {
      case unauthorized
      case httpError(Int)
  }

  // MARK: - URLSession abstraction

  protocol URLSessionProtocol {
      func data(for request: URLRequest) async throws -> (Data, URLResponse)
  }

  extension URLSession: URLSessionProtocol {}

  // MARK: - Client

  final class ClockifyClient {
      private let apiKey: String
      private let session: URLSessionProtocol
      private let baseURL = URL(string: "https://api.clockify.me/api/v1")!

      private lazy var decoder: JSONDecoder = {
          let d = JSONDecoder()
          d.dateDecodingStrategy = .iso8601
          return d
      }()

      private lazy var encoder: JSONEncoder = {
          let e = JSONEncoder()
          e.dateEncodingStrategy = .iso8601
          return e
      }()

      init(apiKey: String, session: URLSessionProtocol = URLSession.shared) {
          self.apiKey = apiKey
          self.session = session
      }

      func fetchUser() async throws -> ClockifyUser {
          try await get(url: baseURL.appendingPathComponent("user"))
      }

      func fetchProjects(workspaceId: String) async throws -> [ClockifyProject] {
          var comps = URLComponents(url: baseURL.appendingPathComponent("workspaces/\(workspaceId)/projects"),
                                    resolvingAgainstBaseURL: false)!
          comps.queryItems = [URLQueryItem(name: "archived", value: "false")]
          return try await get(url: comps.url!)
      }

      func fetchRunningEntry(workspaceId: String, userId: String) async throws -> ClockifyTimeEntry? {
          var comps = URLComponents(
              url: baseURL.appendingPathComponent("workspaces/\(workspaceId)/user/\(userId)/time-entries"),
              resolvingAgainstBaseURL: false)!
          comps.queryItems = [
              URLQueryItem(name: "in-progress", value: "true"),
              URLQueryItem(name: "page-size", value: "1")
          ]
          let entries: [ClockifyTimeEntry] = try await get(url: comps.url!)
          return entries.first
      }

      func stopCurrentTimer(workspaceId: String, userId: String) async throws {
          let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/user/\(userId)/time-entries")
          try await patch(url: url, body: StopTimerBody(end: Date()))
      }

      func startTimer(workspaceId: String, projectId: String) async throws {
          let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries")
          try await post(url: url, body: StartTimerBody(start: Date(), projectId: projectId))
      }

      // MARK: - Helpers

      private func get<T: Decodable>(url: URL) async throws -> T {
          var req = URLRequest(url: url)
          req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
          let (data, response) = try await session.data(for: req)
          try checkResponse(response)
          return try decoder.decode(T.self, from: data)
      }

      private func patch<B: Encodable>(url: URL, body: B) async throws {
          var req = URLRequest(url: url)
          req.httpMethod = "PATCH"
          req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")
          req.httpBody = try encoder.encode(body)
          let (_, response) = try await session.data(for: req)
          try checkResponse(response)
      }

      private func post<B: Encodable>(url: URL, body: B) async throws {
          var req = URLRequest(url: url)
          req.httpMethod = "POST"
          req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")
          req.httpBody = try encoder.encode(body)
          let (_, response) = try await session.data(for: req)
          try checkResponse(response)
      }

      private func checkResponse(_ response: URLResponse) throws {
          guard let http = response as? HTTPURLResponse else { return }
          switch http.statusCode {
          case 200...299: break
          case 401: throw ClockifyError.unauthorized
          default: throw ClockifyError.httpError(http.statusCode)
          }
      }
  }
  ```

- [ ] **Step 4: Run tests — verify they pass**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED|Test Suite)"
  ```
  Expected: All 9 tests pass (4 model + 5 networking).

- [ ] **Step 5: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/ClockifyClient.swift ClockifyWatcherTests/ClockifyClientTests.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add ClockifyClient networking layer"
  ```

---

## Task 5: Elapsed Time Formatting + Hex Color Parsing

**Files:**
- Create: `ClockifyWatcher/Formatting.swift`
- Create: `ClockifyWatcherTests/FormattingTests.swift`

- [ ] **Step 1: Write failing tests**

  Create `ClockifyWatcherTests/FormattingTests.swift`:
  ```swift
  import XCTest
  import AppKit
  @testable import ClockifyWatcher

  final class FormattingTests: XCTestCase {

      // MARK: - Elapsed time

      func testElapsedZeroMinutes() {
          let start = Date(timeIntervalSinceNow: -45)  // 45 seconds ago
          XCTAssertEqual(formatElapsed(from: start), "0:00")
      }

      func testElapsedMinutesPaddedToTwoDigits() {
          let start = Date(timeIntervalSinceNow: -(3 * 60))
          XCTAssertEqual(formatElapsed(from: start), "0:03")
      }

      func testElapsed23Minutes() {
          let start = Date(timeIntervalSinceNow: -((23 * 60) + 45))
          XCTAssertEqual(formatElapsed(from: start), "0:23")
      }

      func testElapsedExactlyOneHour() {
          let start = Date(timeIntervalSinceNow: -3600)
          XCTAssertEqual(formatElapsed(from: start), "1:00")
      }

      func testElapsedMultipleHoursAndMinutes() {
          let start = Date(timeIntervalSinceNow: -((2 * 3600) + (5 * 60)))
          XCTAssertEqual(formatElapsed(from: start), "2:05")
      }

      // MARK: - Hex color

      func testHexColorWithHash() {
          XCTAssertNotNil(NSColor(hex: "#FF5722"))
      }

      func testHexColorWithoutHash() {
          XCTAssertNotNil(NSColor(hex: "FF5722"))
      }

      func testHexColorComponents() {
          let color = NSColor(hex: "#FF0000")!.usingColorSpace(.sRGB)!
          XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.01)
          XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.01)
          XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.01)
      }

      func testHexColorInvalidReturnsNil() {
          XCTAssertNil(NSColor(hex: "ZZZZZZ"))
          XCTAssertNil(NSColor(hex: "short"))
          XCTAssertNil(NSColor(hex: ""))
      }
  }
  ```

- [ ] **Step 2: Run tests — verify they fail**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED)"
  ```
  Expected: compile errors — `formatElapsed` and `NSColor(hex:)` not defined.

- [ ] **Step 3: Implement Formatting.swift**

  Create `ClockifyWatcher/Formatting.swift`:
  ```swift
  import AppKit

  func formatElapsed(from start: Date) -> String {
      let seconds = Int(Date().timeIntervalSince(start))
      let hours = seconds / 3600
      let minutes = (seconds % 3600) / 60
      return "\(hours):\(String(format: "%02d", minutes))"
  }

  extension NSColor {
      convenience init?(hex: String) {
          let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
          guard stripped.count == 6, let value = UInt64(stripped, radix: 16) else { return nil }
          let r = CGFloat((value >> 16) & 0xFF) / 255
          let g = CGFloat((value >> 8) & 0xFF) / 255
          let b = CGFloat(value & 0xFF) / 255
          self.init(srgbRed: r, green: g, blue: b, alpha: 1)
      }
  }
  ```

- [ ] **Step 4: Run tests — verify they pass**

  ```bash
  xcodebuild test -project ~/Code/clockify-watcher/ClockifyWatcher.xcodeproj \
    -scheme ClockifyWatcher -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED|Test Suite)"
  ```
  Expected: All 9 tests pass (5 formatting + 4 hex color).

- [ ] **Step 5: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/Formatting.swift ClockifyWatcherTests/FormattingTests.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add elapsed time formatting and hex color parsing"
  ```

---

## Task 6: AppDelegate — StatusItem + Logo

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift`
- Modify: `ClockifyWatcher/Assets.xcassets` (via Xcode GUI)

- [ ] **Step 1: Add Clockify logo to Assets.xcassets**

  In Xcode's Assets.xcassets editor:
  1. Click `+` at the bottom left → New Image Set
  2. Name it `clockify-logo`
  3. In the Attributes inspector (right panel), set **Render As** → **Template Image**
  4. Drag a monochrome PNG/PDF into the `1x` slot

  If you don't have the Clockify logo yet: any solid-color square PNG works as a placeholder. Template images are rendered in the button's tint color (white in dark mode, black in light mode) automatically.

- [ ] **Step 2: Replace AppDelegate.swift with full skeleton**

  Replace `ClockifyWatcher/AppDelegate.swift`:
  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem!
      private var pollTimer: Timer?

      var consecutiveFailures = 0
      var cachedProjects: [String: ClockifyProject] = [:]
      var activeProjectId: String?
      var activeEntryStart: Date?
      var workspaceId: String?
      var userId: String?
      var client: ClockifyClient?

      func applicationDidFinishLaunching(_ notification: Notification) {
          setupStatusItem()
          startSession()
      }

      // MARK: - StatusItem setup

      private func setupStatusItem() {
          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
          guard let button = statusItem.button else { return }
          button.image = NSImage(named: "clockify-logo")
          button.image?.isTemplate = true
          button.imagePosition = .imageLeft
          let menu = buildMenu()
          menu.delegate = self
          statusItem.menu = menu
      }

      // MARK: - StatusItem display update

      func updateStatusItem() {
          guard let button = statusItem.button else { return }
          if let projectId = activeProjectId,
             let project = cachedProjects[projectId],
             let start = activeEntryStart,
             let color = NSColor(hex: project.color) {
              let prefix = consecutiveFailures >= 2 ? "*" : ""
              let text = "\(prefix)\(formatElapsed(from: start)) \(project.name)"
              let attrs: [NSAttributedString.Key: Any] = [
                  .foregroundColor: color,
                  .font: NSFont.menuBarFont(ofSize: 0)
              ]
              button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
          } else if consecutiveFailures >= 2 {
              button.attributedTitle = NSAttributedString(string: "*")
          } else {
              button.attributedTitle = NSAttributedString(string: "")
          }
          // Rebuild menu so checkmarks stay current
          let menu = buildMenu()
          menu.delegate = self
          statusItem.menu = menu
      }

      // MARK: - Session management

      private func startSession() {
          guard let apiKey = KeychainHelper.loadApiKey() else {
              promptForApiKey()
              return
          }
          client = ClockifyClient(apiKey: apiKey)
          Task { await initialize() }
      }

      // Stubs — implemented in Tasks 7 and 8
      func promptForApiKey(error: String? = nil) {}
      func initialize() async {}
      func buildMenu() -> NSMenu { NSMenu() }
  }

  extension AppDelegate: NSMenuDelegate {
      func menuWillOpen(_ menu: NSMenu) {
          Task { await refreshProjects() }
      }
  }
  ```

- [ ] **Step 3: Build and verify**

  Product → Build (⌘B). Launch the app. Expected: Clockify logo appears in the menubar. Clicking it shows an empty menu (no projects yet — that's correct).

- [ ] **Step 4: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/AppDelegate.swift ClockifyWatcher/Assets.xcassets
  git -C ~/Code/clockify-watcher commit -m "feat: add NSStatusItem with Clockify logo and skeleton"
  ```

---

## Task 7: First-Run API Key Setup

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift`

- [ ] **Step 1: Replace the `promptForApiKey` stub**

  Find `func promptForApiKey(error: String? = nil) {}` in `AppDelegate.swift` and replace it with:
  ```swift
      func promptForApiKey(error: String? = nil) {
          let alert = NSAlert()
          alert.messageText = error ?? "Clockify API Key Required"
          alert.informativeText = "Find your API key in Clockify → Profile Settings → API."
          alert.addButton(withTitle: "Connect")
          alert.addButton(withTitle: "Quit")

          let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
          input.placeholderString = "Paste your API key here"
          alert.accessoryView = input
          alert.window.initialFirstResponder = input

          guard alert.runModal() == .alertFirstButtonReturn else {
              NSApplication.shared.terminate(nil)
              return
          }

          let key = input.stringValue.trimmingCharacters(in: .whitespaces)
          guard !key.isEmpty else {
              promptForApiKey(error: "API key cannot be empty.")
              return
          }

          Task {
              let tempClient = ClockifyClient(apiKey: key)
              do {
                  _ = try await tempClient.fetchUser()
                  KeychainHelper.saveApiKey(key)
                  self.client = tempClient
                  await self.initialize()
              } catch ClockifyError.unauthorized {
                  await MainActor.run {
                      self.promptForApiKey(error: "Invalid API key. Please try again.")
                  }
              } catch {
                  await MainActor.run {
                      self.promptForApiKey(error: "Connection failed. Check your network and try again.")
                  }
              }
          }
      }
  ```

- [ ] **Step 2: Build and manual test**

  Build and run. To test:
  1. Open **Keychain Access.app** → search "clockify-watcher" → delete the entry if it exists
  2. Launch the app — the API key prompt should appear immediately
  3. Click Connect with an empty field — should re-prompt with "API key cannot be empty."
  4. Enter a fake key (e.g. `aaabbbccc`) — should re-prompt with "Invalid API key."
  5. Enter your real Clockify API key — should accept it (no error) and close the alert

  Your API key is at clockify.me → Profile Settings → API (bottom of page).

- [ ] **Step 3: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/AppDelegate.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add first-run API key prompt with validation"
  ```

---

## Task 8: Launch Sequence + Poll Loop

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift`

- [ ] **Step 1: Replace the `initialize` stub**

  Find `func initialize() async {}` and replace it:
  ```swift
      func initialize() async {
          guard let client else { return }
          do {
              let user = try await client.fetchUser()
              userId = user.id
              workspaceId = user.activeWorkspace
              let projects = try await client.fetchProjects(workspaceId: user.activeWorkspace)
              cachedProjects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
          } catch ClockifyError.unauthorized {
              await MainActor.run {
                  KeychainHelper.deleteApiKey()
                  promptForApiKey(error: "Session expired. Please re-enter your API key.")
              }
              return
          } catch {
              // Network error on launch — will retry on next poll
          }
          await MainActor.run { startPolling() }
      }
  ```

- [ ] **Step 2: Add startPolling, poll, and refreshProjects**

  Add these methods to `AppDelegate`:
  ```swift
      private func startPolling() {
          poll()
          pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
              self?.poll()
          }
      }

      func poll() {
          guard let client, let workspaceId, let userId else { return }
          Task {
              do {
                  let entry = try await client.fetchRunningEntry(workspaceId: workspaceId, userId: userId)
                  await MainActor.run {
                      self.consecutiveFailures = 0
                      if let entry, let projectId = entry.projectId {
                          self.activeProjectId = projectId
                          self.activeEntryStart = entry.timeInterval.start
                          if self.cachedProjects[projectId] == nil {
                              Task { await self.refreshProjects() }
                          }
                      } else {
                          self.activeProjectId = nil
                          self.activeEntryStart = nil
                      }
                      self.updateStatusItem()
                  }
              } catch ClockifyError.unauthorized {
                  await MainActor.run {
                      self.pollTimer?.invalidate()
                      KeychainHelper.deleteApiKey()
                      self.promptForApiKey(error: "Session expired. Please re-enter your API key.")
                  }
              } catch {
                  await MainActor.run {
                      self.consecutiveFailures += 1
                      self.updateStatusItem()
                  }
              }
          }
      }

      func refreshProjects() async {
          guard let client, let workspaceId else { return }
          do {
              let projects = try await client.fetchProjects(workspaceId: workspaceId)
              await MainActor.run {
                  self.cachedProjects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
                  self.updateStatusItem()
              }
          } catch {
              // Silently ignore — retry on next menu open or unknown projectId
          }
      }
  ```

- [ ] **Step 3: Build and manual test**

  Build and run with your API key saved in Keychain:
  - Start a timer in Clockify on any project
  - Within a few seconds the menubar should show `H:MM ProjectName` in the project's color
  - Stop the timer in Clockify — within 30s the menubar should revert to just the logo
  - Turn off your network connection — after 2 polls (~1 minute) a `*` prefix should appear

- [ ] **Step 4: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/AppDelegate.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add launch sequence, poll loop, and stale indicator"
  ```

---

## Task 9: Menu — Project List, Switch, Links, Quit

**Files:**
- Modify: `ClockifyWatcher/AppDelegate.swift`

- [ ] **Step 1: Replace the `buildMenu` stub**

  Find `func buildMenu() -> NSMenu { NSMenu() }` and replace it:
  ```swift
      func buildMenu() -> NSMenu {
          let menu = NSMenu()

          let sortedProjects = cachedProjects.values.sorted { $0.name < $1.name }
          for project in sortedProjects {
              let item = NSMenuItem(title: project.name,
                                    action: #selector(switchProject(_:)),
                                    keyEquivalent: "")
              item.representedObject = project.id
              item.target = self
              item.state = project.id == activeProjectId ? .on : .off
              menu.addItem(item)
          }

          menu.addItem(.separator())

          let openApp = NSMenuItem(title: "Open Clockify App",
                                   action: #selector(openClockifyApp),
                                   keyEquivalent: "")
          openApp.target = self
          menu.addItem(openApp)

          let openBrowser = NSMenuItem(title: "Open in Browser",
                                       action: #selector(openInBrowser),
                                       keyEquivalent: "")
          openBrowser.target = self
          menu.addItem(openBrowser)

          menu.addItem(.separator())

          menu.addItem(NSMenuItem(title: "Quit",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q"))
          return menu
      }

      @objc func switchProject(_ sender: NSMenuItem) {
          guard let projectId = sender.representedObject as? String,
                projectId != activeProjectId,
                let client, let workspaceId, let userId else { return }
          Task {
              do {
                  if activeProjectId != nil {
                      try await client.stopCurrentTimer(workspaceId: workspaceId, userId: userId)
                  }
                  try await client.startTimer(workspaceId: workspaceId, projectId: projectId)
                  poll()
              } catch {
                  await MainActor.run {
                      let alert = NSAlert()
                      alert.messageText = "Failed to switch project"
                      alert.informativeText = error.localizedDescription
                      alert.runModal()
                  }
              }
          }
      }

      @objc func openClockifyApp() {
          let appURL = URL(fileURLWithPath: "/Applications/Clockify.app")
          if NSWorkspace.shared.open(appURL) { return }
          openInBrowser()
      }

      @objc func openInBrowser() {
          NSWorkspace.shared.open(URL(string: "https://app.clockify.me")!)
      }
  ```

- [ ] **Step 2: Build and full manual test**

  Build and run. Verify:
  - [ ] Clicking the menubar item shows all active projects sorted alphabetically
  - [ ] The currently running project has a checkmark (`✓`)
  - [ ] Clicking a different project stops the current timer and starts the new one (check Clockify to confirm)
  - [ ] Clicking the same project (already checked) does nothing
  - [ ] Clicking "Open in Browser" opens `app.clockify.me`
  - [ ] Clicking "Open Clockify App" opens the app (or falls back to browser if not installed)
  - [ ] Clicking "Quit" terminates the app
  - [ ] After clicking the menu, the project list refreshes in the background (add a project in Clockify web, open menu, wait a few seconds, open menu again — new project appears)

- [ ] **Step 3: Commit**

  ```bash
  git -C ~/Code/clockify-watcher add ClockifyWatcher/AppDelegate.swift
  git -C ~/Code/clockify-watcher commit -m "feat: add project menu with switching, links, and quit"
  ```
