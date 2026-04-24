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
    func refreshProjects() async {}
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Task { await refreshProjects() }
    }
}
