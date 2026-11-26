import AppKit

final class MenuBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let cli = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/lidkill")
    private let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lidkill", isDirectory: true)
    private let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/lidkill.log")
    private let commandQueue = DispatchQueue(label: "com.lidkill.menubar.commands")
    private let menu = NSMenu()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var configSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var previewDeadline: TimeInterval?
    private var previewShowsPage = false
    private var pendingDeadline: TimeInterval?
    private var pendingShowsPage = false
    private var pageDeadline: TimeInterval?
    private var livePage: LidPage?
    private var websitePreview: LidPage?
    private var armed = false
    private var dryRun = false
    private var launchAtSignIn = false
    private var configuredDelay = 1
    private var headline: NSMenuItem!
    private var countdown: NSMenuItem!
    private var cancel: NSMenuItem!
    private var arm: NSMenuItem!
    private var dryRunItem: NSMenuItem!
    private var modeItem: NSMenuItem!
    private var delayItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var pageItem: NSMenuItem!
    private var previewWebsite: NSMenuItem!
    private var testWebsite: NSMenuItem!
    private var clearWebsite: NSMenuItem!

    private var pageURLFile: URL { configDirectory.appendingPathComponent("page-url") }
    private var configuredPageURL: URL? {
        (try? String(contentsOf: pageURLFile, encoding: .utf8)).flatMap(LidPage.websiteURL)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "Lidkill", withExtension: "png"),
           let asset = NSImage(contentsOf: iconURL),
           let source = asset.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let glyph = source.copy(maskingColorComponents: [128, 255, 128, 255, 128, 255]) {
            let icon = NSImage(cgImage: glyph, size: NSSize(width: 17, height: 17))
            icon.isTemplate = true
            statusItem.button?.image = icon
        }
        if statusItem.button?.image == nil {
            statusItem.button?.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Lidkill")
        }
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        statusItem.button?.setAccessibilityLabel("Lidkill")
        statusItem.button?.toolTip = "Lidkill"
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        headline = add("Lidkill", to: menu)
        headline.isEnabled = false
        countdown = add("", to: menu)
        countdown.isEnabled = false
        cancel = add("Cancel Pending Action", to: menu, action: #selector(cancelCountdown))
        menu.addItem(.separator())
        arm = add("Arm…", to: menu, action: #selector(toggleArmed))
        dryRunItem = add("Dry Run", to: menu, action: #selector(toggleDryRun))
        modeItem = add("Lid Action", to: menu)
        modeItem.submenu = choices(
            [("Power Off", "poweroff"), ("Restart", "reboot"),
             ("Hard Shutdown", "hard"), ("Hard Restart", "hard-restart"),
             ("Emergency Shutdown", "nuke")], action: #selector(setMode(_:))
        )
        delayItem = add("Delay", to: menu)
        delayItem.submenu = choices(
            [0, 1, 3, 5, 10, 25, 30, 60].map { ($0 == 0 ? "Immediate" : "\($0)s", String($0)) },
            action: #selector(setDelay(_:))
        )
        if let delays = delayItem.submenu {
            _ = add("Custom…", to: delays, action: #selector(setCustomDelay))
        }
        let pageMenu = NSMenu()
        pageMenu.autoenablesItems = false
        pageItem = add("Lid Page", to: menu)
        pageItem.submenu = pageMenu
        pageItem.isEnabled = true
        _ = add("Set Website…", to: pageMenu, action: #selector(setWebsite))
        previewWebsite = add("Preview Website", to: pageMenu, action: #selector(showWebsitePreview))
        testWebsite = add("Test Countdown With Website", to: pageMenu, action: #selector(testWebsiteCountdown))
        clearWebsite = add("Disable Lid Page", to: pageMenu, action: #selector(disableWebsite))
        menu.addItem(.separator())
        loginItem = add("Launch at Sign-In", to: menu, action: #selector(toggleLogin))
        _ = add("Preview Countdown", to: menu, action: #selector(preview))
        _ = add("Setup Status…", to: menu, action: #selector(showSetupStatus))
        _ = add("Open Log", to: menu, action: #selector(openLog))
        for control in [arm, dryRunItem, modeItem, delayItem, loginItem] {
            control?.isEnabled = false
        }

        observeCountdown()
        reloadCountdown()
        refreshSettings()
    }

    func menuWillOpen(_ menu: NSMenu) {
        reloadCountdown()
        refreshSettings()
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func choices(_ values: [(String, String)], action: Selector) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (label, value) in values {
            add(label, to: submenu, action: action).representedObject = value
        }
        return submenu
    }

    private func run(_ arguments: [String], completion: @escaping (Int32, String) -> Void) {
        let executable = cli
        commandQueue.async {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let message = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { completion(process.terminationStatus, message) }
            } catch {
                DispatchQueue.main.async { completion(1, error.localizedDescription) }
            }
        }
    }

    private func refreshSettings() {
        let page = configuredPageURL
        let hasPage = page != nil
        if let host = page?.host {
            pageItem.title = "Lid Page · " + (host.count <= 28 ? host : String(host.prefix(27)) + "…")
        } else {
            pageItem.title = "Lid Page · Off"
        }
        pageItem.isEnabled = pageDeadline == nil
        previewWebsite.isEnabled = hasPage && pageDeadline == nil
        testWebsite.isEnabled = hasPage && pageDeadline == nil
        clearWebsite.isEnabled = hasPage && pageDeadline == nil
        run(["menu-status"]) { [weak self] status, message in
            guard let self else { return }
            let fields = message.split(separator: "\n")
            let available = status == 0 && fields.count == 5
            self.arm.isEnabled = available
            self.dryRunItem.isEnabled = available
            self.modeItem.isEnabled = available
            self.delayItem.isEnabled = available
            self.loginItem.isEnabled = available
            guard available else {
                self.headline.title = "Lidkill · CLI Unavailable"
                return
            }
            self.armed = fields[0] == "1"
            self.dryRun = fields[3] == "1"
            self.launchAtSignIn = fields[4] == "1"
            self.headline.title = self.armed ? "Lidkill · Armed" : "Lidkill · Disarmed"
            self.arm.title = self.armed ? "Disarm…" : "Arm…"
            self.dryRunItem.state = self.dryRun ? .on : .off
            self.loginItem.state = self.launchAtSignIn ? .on : .off
            let mode = String(fields[1])
            if let choices = self.modeItem.submenu?.items {
                self.modeItem.title = "Lid Action · " +
                    (choices.first { $0.representedObject as? String == mode }?.title ?? mode)
                for choice in choices {
                    choice.state = choice.representedObject as? String == mode ? .on : .off
                }
            }
            let delay = String(fields[2])
            self.configuredDelay = Int(delay) ?? (hasPage ? 25 : 1)
            self.delayItem.title = delay == "0" ? "Delay · Immediate" : "Delay · \(delay)s"
            for choice in self.delayItem.submenu?.items ?? [] {
                choice.state = choice.representedObject as? String == delay ? .on : .off
            }
        }
    }

    private func observeCountdown() {
        let descriptor = Darwin.open(configDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in self?.reloadCountdown() }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        configSource = source
    }

    private func reloadCountdown() {
        let path = configDirectory.appendingPathComponent("pending")
        let pending = (try? String(contentsOf: path, encoding: .utf8))?.split(separator: "\n") ?? []
        pendingDeadline = pending.first.flatMap { TimeInterval($0) }
        pendingShowsPage = pending.last == "page"
        refreshCountdown()
    }

    private func refreshCountdown() {
        let now = Date().timeIntervalSince1970
        let live = pendingDeadline
            .flatMap { (now - 2 ... now + 60).contains($0) ? $0 : nil }
        if live != nil || (previewDeadline ?? .infinity) <= now {
            previewDeadline = nil
            previewShowsPage = false
        }
        let siteDeadline = pendingShowsPage ? live : nil
        refreshLidPage(siteDeadline ?? (previewShowsPage ? previewDeadline : nil), now: now, simulation: live == nil)
        let deadline = live ?? previewDeadline
        countdown.isHidden = deadline == nil
        cancel.isHidden = deadline == nil
        cancel.title = previewDeadline == nil ? "Cancel Pending Action" : "Cancel Preview"

        if let deadline {
            let seconds = max(0, Int(ceil(deadline - now)))
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.imagePosition = .noImage
            statusItem.button?.title = String(seconds)
            countdown.title = previewDeadline == nil ? "Lid Action in \(seconds)s" : "Preview · \(seconds)s"
            if timer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    self?.refreshCountdown()
                }
                timer.tolerance = 0.1
                RunLoop.main.add(timer, forMode: .common)
                RunLoop.main.add(timer, forMode: .eventTracking)
                self.timer = timer
            }
        } else {
            let hasIcon = statusItem.button?.image != nil
            statusItem.length = hasIcon ? NSStatusItem.squareLength : NSStatusItem.variableLength
            statusItem.button?.imagePosition = hasIcon ? .imageOnly : .noImage
            statusItem.button?.title = hasIcon ? "" : "Lidkill"
            timer?.invalidate()
            timer = nil
        }
    }

    private func refreshLidPage(_ deadline: TimeInterval?, now: TimeInterval, simulation: Bool) {
        if deadline != pageDeadline {
            pageDeadline = deadline
            livePage?.close()
            livePage = nil
        }
        guard let deadline else { return }
        let seconds = max(0, Int(ceil(deadline - now)))
        if livePage == nil, seconds > 0, let url = configuredPageURL,
           let page = LidPage(url: url, simulation: simulation, cancel: { [weak self] in self?.cancelCountdown() }) {
            websitePreview?.close()
            websitePreview = nil
            livePage = page
            page.updateCountdown(seconds)
            page.show()
        } else {
            livePage?.updateCountdown(seconds)
        }
    }

    private func update(_ arguments: [String]) {
        run(arguments) { [weak self] status, message in
            guard let self else { return }
            if status != 0 { self.showMessage(message) }
            self.refreshSettings()
            self.reloadCountdown()
        }
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Lidkill"
        alert.informativeText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func preview() {
        previewShowsPage = false
        previewDeadline = Date().timeIntervalSince1970 + 5
        reloadCountdown()
    }

    @objc private func testWebsiteCountdown() {
        reloadCountdown()
        let now = Date().timeIntervalSince1970
        guard configuredPageURL != nil, (pendingDeadline ?? 0) <= now else { return }
        previewShowsPage = true
        previewDeadline = now + TimeInterval(max(1, configuredDelay))
        reloadCountdown()
    }

    @objc private func cancelCountdown() {
        if previewDeadline != nil {
            previewDeadline = nil
            previewShowsPage = false
            refreshCountdown()
        } else {
            update(["cancel"])
        }
    }

    @objc private func toggleArmed() {
        guard let script = Bundle.main.url(forResource: armed ? "off" : "on", withExtension: "command"),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else {
            showMessage("Terminal is required for the administrator prompt.")
            return
        }
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: .init()) { [weak self] _, error in
            if let error {
                DispatchQueue.main.async { self?.showMessage(error.localizedDescription) }
            }
        }
    }

    @objc private func toggleDryRun() { update(["dryrun", dryRun ? "off" : "on"]) }

    @objc private func toggleLogin() { update(["login", launchAtSignIn ? "off" : "on"]) }

    @objc private func showSetupStatus() {
        run(["doctor"]) { [weak self] _, report in self?.showMessage(report) }
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        if value == "nuke" {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Enable emergency shutdown?"
            alert.informativeText = "This immediately stops macOS without flushing the disk when the lid action fires. Unsaved work and filesystem data may be lost."
            alert.addButton(withTitle: "Keep Current Action")
            alert.addButton(withTitle: "Enable Emergency Shutdown")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        update(["mode", value])
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { update(["delay", value]) }
    }

    @objc private func setCustomDelay() {
        let alert = NSAlert()
        alert.messageText = "Set Countdown Delay"
        alert.informativeText = "Enter a whole number of seconds from 0 to 60."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(configuredDelay)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.addButton(withTitle: "Save Delay")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let delay = Int(input.stringValue.trimmingCharacters(in: .whitespaces)), (0...60).contains(delay) else {
            showMessage("Enter a whole number from 0 to 60.")
            return
        }
        update(["delay", String(delay)])
    }

    @objc private func setWebsite() {
        guard pageDeadline == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Set Lid Page Website"
        alert.informativeText = "The default is a hard shutdown after 25 seconds. Reopening the lid keeps the countdown going. You can change the action and delay from the menu."
        let address = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        address.placeholderString = "https://"
        address.stringValue = configuredPageURL?.absoluteString ?? ""
        alert.accessoryView = address
        alert.window.initialFirstResponder = address
        alert.addButton(withTitle: "Save Website")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = LidPage.websiteURL(address.stringValue) else {
            showMessage("Enter a valid HTTP or HTTPS URL.")
            return
        }
        do {
            try Data((url.absoluteString + "\n").utf8).write(to: pageURLFile, options: .atomic)
            refreshSettings()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    @objc private func showWebsitePreview() {
        guard pageDeadline == nil, let url = configuredPageURL else { return }
        websitePreview?.close()
        websitePreview = LidPage(url: url)
        websitePreview?.show()
    }

    @objc private func disableWebsite() {
        guard pageDeadline == nil else { return }
        do {
            try FileManager.default.removeItem(at: pageURLFile)
            websitePreview?.close()
            websitePreview = nil
            refreshSettings()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    @objc private func openLog() {
        if !NSWorkspace.shared.open(log) { showMessage("The watcher has not created a log yet.") }
    }

}

@main
enum LidkillApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--replace-menu"), let identifier = Bundle.main.bundleIdentifier {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                where app.processIdentifier != getpid() && app.bundleURL == Bundle.main.bundleURL {
                _ = app.terminate()
            }
        }
        let menuBar = MenuBar()
        application.delegate = menuBar
        withExtendedLifetime(menuBar) { application.run() }
    }
}
