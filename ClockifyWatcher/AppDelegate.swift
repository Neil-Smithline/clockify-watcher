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
        // Update checkmarks in the existing menu rather than rebuilding
        updateMenuCheckmarks()
    }

    func updateMenuCheckmarks() {
        guard let menu = statusItem.menu else { return }
        for item in menu.items {
            guard let projectId = item.representedObject as? String else { continue }
            item.state = projectId == activeProjectId ? .on : .off
        }
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

    func buildMenu() -> NSMenu { NSMenu() }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Task { await refreshProjects() }
    }
}
