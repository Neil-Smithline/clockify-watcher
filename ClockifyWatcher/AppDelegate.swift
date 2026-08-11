import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var displayTimer: Timer?

    var consecutiveFailures = 0
    var cachedProjects: [String: ClockifyProject] = [:]
    /// The running entry, cached from the last poll. Non-nil only when it has a project.
    var activeEntry: ClockifyTimeEntry?
    var activeProjectId: String? { activeEntry?.projectId }
    var activeEntryStart: Date? { activeEntry?.timeInterval.start }
    var workspaceId: String?
    var userId: String?
    var client: ClockifyClient?
    var lastAutoStoppedProjectId: String?
    var noProjectEntryId: String?

    private let autoStoppedProjectKey = "lastAutoStoppedProjectId"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerSystemEventObservers()
        registerLoginItem()
        startSession()
    }

    // MARK: - StatusItem setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "clock", accessibilityDescription: "Clockify") ?? NSImage(named: "clockify-logo")
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeft
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - System event handling

    private func registerSystemEventObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(handleAutoStop),
                             name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleAutoStop),
                             name: NSWorkspace.willPowerOffNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleAutoStop),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(handleScreenUnlock),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func handleAutoStop() {
        let stoppedProjectId = activeProjectId
        stopTimerSync()
        if let projectId = stoppedProjectId {
            lastAutoStoppedProjectId = projectId
            UserDefaults.standard.set(projectId, forKey: autoStoppedProjectKey)
        }
    }

    @objc private func handleScreenUnlock() {
        guard activeProjectId == nil, lastAutoStoppedProjectId != nil else { return }
        showResumeDialog()
    }

    private func stopTimerSync() {
        guard let client, let workspaceId, let userId, activeProjectId != nil else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await client.stopCurrentTimer(workspaceId: workspaceId, userId: userId)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 8)
        DispatchQueue.main.async {
            self.activeEntry = nil
            self.updateStatusItem()
        }
    }

    // MARK: - Resume dialog

    private func clearAutoStoppedProject() {
        lastAutoStoppedProjectId = nil
        UserDefaults.standard.removeObject(forKey: autoStoppedProjectKey)
    }

    private func showResumeDialog() {
        guard lastAutoStoppedProjectId != nil, !cachedProjects.isEmpty else {
            clearAutoStoppedProject()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Timer was automatically stopped"
        alert.addButton(withTitle: "Start Timer")
        alert.addButton(withTitle: "Dismiss")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        let sorted = cachedProjects.values.sorted { $0.name < $1.name }
        for project in sorted {
            popup.addItem(withTitle: project.name)
            popup.lastItem?.representedObject = project.id
        }
        if let idx = sorted.firstIndex(where: { $0.id == lastAutoStoppedProjectId }) {
            popup.selectItem(at: idx)
        }
        alert.accessoryView = popup

        clearAutoStoppedProject()

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let selectedId = popup.selectedItem?.representedObject as? String,
              let client, let workspaceId else { return }
        Task {
            try? await client.startTimer(workspaceId: workspaceId, projectId: selectedId)
            poll()
        }
    }

    private func showNoProjectDialog(entry: ClockifyTimeEntry) {
        let entryId = entry.id
        guard !cachedProjects.isEmpty, let client, let workspaceId else { return }

        let alert = NSAlert()
        alert.messageText = "Timer running without a project"
        alert.addButton(withTitle: "Assign Project")
        alert.addButton(withTitle: "Delete Timer")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        let sorted = cachedProjects.values.sorted { $0.name < $1.name }
        for project in sorted {
            popup.addItem(withTitle: project.name)
            popup.lastItem?.representedObject = project.id
        }
        alert.accessoryView = popup

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn,
           let selectedId = popup.selectedItem?.representedObject as? String {
            Task {
                try? await client.updateEntry(workspaceId: workspaceId, entryId: entryId,
                                              start: entry.timeInterval.start,
                                              projectId: selectedId,
                                              description: entry.description,
                                              taskId: entry.taskId, tagIds: entry.tagIds)
                await MainActor.run { self.noProjectEntryId = nil }
                poll()
            }
        } else if response == .alertSecondButtonReturn {
            Task {
                try? await client.deleteEntry(workspaceId: workspaceId, entryId: entryId)
                await MainActor.run { self.noProjectEntryId = nil }
                poll()
            }
        }
    }

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

    // MARK: - Login item

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: - StatusItem display update

    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let prefix = consecutiveFailures >= 2 ? "*" : ""
        if let projectId = activeProjectId,
           let project = cachedProjects[projectId],
           let start = activeEntryStart,
           let color = NSColor(hex: project.color) {
            let text = "\(prefix)\(formatElapsed(from: start)) \(project.name)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.menuBarFont(ofSize: 0)
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else if let start = activeEntryStart {
            // Timer running but project not yet in cache — show time without project name
            button.attributedTitle = NSAttributedString(string: "\(prefix)\(formatElapsed(from: start))")
        } else if consecutiveFailures >= 2 {
            button.attributedTitle = NSAttributedString(string: "*")
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
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
            if let saved = UserDefaults.standard.string(forKey: autoStoppedProjectKey) {
                UserDefaults.standard.removeObject(forKey: autoStoppedProjectKey)
                let entry = try? await client.fetchRunningEntry(workspaceId: user.activeWorkspace, userId: user.id)
                if entry?.projectId == nil {
                    await MainActor.run { self.lastAutoStoppedProjectId = saved }
                }
            }
        } catch ClockifyError.unauthorized {
            await MainActor.run {
                KeychainHelper.deleteApiKey()
                promptForApiKey(error: "Session expired. Please re-enter your API key.")
            }
            return
        } catch {
            // Network error on launch — will retry on next poll
        }
        await MainActor.run {
            startPolling()
            if lastAutoStoppedProjectId != nil { showResumeDialog() }
        }
    }

    private func startPolling() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.poll()
        }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func poll() {
        guard let client, let workspaceId, let userId else { return }
        Task {
            do {
                let entry = try await client.fetchRunningEntry(workspaceId: workspaceId, userId: userId)
                await MainActor.run {
                    self.consecutiveFailures = 0
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
                    self.updateStatusItem()
                }
            } catch ClockifyError.unauthorized {
                await MainActor.run {
                    self.pollTimer?.invalidate()
                    self.displayTimer?.invalidate()
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

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

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

    @objc func editStartTime() {
        showEditStartTimeDialog()
    }

    @objc func stopTimer() {
        guard let client, let workspaceId, let userId else { return }
        Task {
            do {
                try await client.stopCurrentTimer(workspaceId: workspaceId, userId: userId)
                poll()
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to stop timer"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    @objc func openClockifyApp() {
        let candidates = [
            "/Applications/Clockify Desktop.app",
            "/Applications/Clockify.app",
            "\(NSHomeDirectory())/Applications/Clockify Desktop.app",
            "\(NSHomeDirectory())/Applications/Clockify.app"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil)
                return
            }
        }
        openInBrowser()
    }

    @objc func openInBrowser() {
        NSWorkspace.shared.open(URL(string: "https://app.clockify.me")!)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        populateMenu(menu)
        poll()
        Task { await refreshProjects() }
    }
}
