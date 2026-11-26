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
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var configSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var previewDeadline: TimeInterval?
    private var pageDeadline: TimeInterval?
    private var livePage: LidPage?
    private var websitePreview: LidPage?
    private var armed = false
    private var dryRun = false
    private var headline: NSMenuItem!
    private var countdown: NSMenuItem!
    private var cancel: NSMenuItem!
    private var arm: NSMenuItem!
    private var dryRunItem: NSMenuItem!
    private var modeItem: NSMenuItem!
    private var delayItem: NSMenuItem!
    private var previewWebsite: NSMenuItem!
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
            statusItem.button?.imagePosition = .imageLeading
        }
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
             ("Hard Shutdown", "hard"), ("Hard Restart", "hard-restart")], action: #selector(setMode(_:))
        )
        delayItem = add("Delay", to: menu)
        delayItem.submenu = choices(
            [0, 1, 3, 5, 10, 25, 30, 60].map { ($0 == 0 ? "Immediate" : "\($0)s", String($0)) },
            action: #selector(setDelay(_:))
        )
        let pageMenu = NSMenu()
        pageMenu.autoenablesItems = false
        add("Lid Page", to: menu).submenu = pageMenu
        _ = add("Set Website…", to: pageMenu, action: #selector(setWebsite))
        previewWebsite = add("Preview Website", to: pageMenu, action: #selector(showWebsitePreview))
        clearWebsite = add("Disable Lid Page", to: pageMenu, action: #selector(disableWebsite))
        menu.addItem(.separator())
        _ = add("Preview Countdown", to: menu, action: #selector(preview))
        _ = add("Open Log", to: menu, action: #selector(openLog))
        _ = add("Quit Until Next Sign-In", to: menu, action: #selector(quit))
        for control in [arm, dryRunItem, modeItem, delayItem] {
            control?.isEnabled = false
        }

        observeCountdown()
        refreshCountdown()
        refreshSettings()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshCountdown()
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
        let hasPage = configuredPageURL != nil
        previewWebsite.isEnabled = hasPage && pageDeadline == nil
        clearWebsite.isEnabled = hasPage && pageDeadline == nil
        run(["menu-status"]) { [weak self] status, message in
            guard let self else { return }
            let fields = message.split(separator: "\n")
            let available = status == 0 && fields.count == 4
            self.arm.isEnabled = available
            self.dryRunItem.isEnabled = available
            self.modeItem.isEnabled = available
            self.delayItem.isEnabled = available
            guard available else {
                self.headline.title = "Lidkill · CLI Unavailable"
                return
            }
            self.armed = fields[0] == "1"
            self.dryRun = fields[3] == "1"
            self.headline.title = self.armed ? "Lidkill · Armed" : "Lidkill · Disarmed"
            self.arm.title = self.armed ? "Disarm…" : "Arm…"
            self.dryRunItem.state = self.dryRun ? .on : .off
            let mode = String(fields[1])
            if let choices = self.modeItem.submenu?.items {
                self.modeItem.title = "Lid Action · " +
                    (choices.first { $0.representedObject as? String == mode }?.title ?? mode)
                for choice in choices {
                    choice.state = choice.representedObject as? String == mode ? .on : .off
                }
            }
            let delay = String(fields[2])
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
        source.setEventHandler { [weak self] in self?.refreshCountdown() }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        configSource = source
    }

    private func refreshCountdown() {
        let now = Date().timeIntervalSince1970
        let path = configDirectory.appendingPathComponent("pending")
        let pending = (try? String(contentsOf: path, encoding: .utf8))?.split(separator: "\n") ?? []
        let live = pending.first.flatMap { TimeInterval($0) }
            .flatMap { (now - 2 ... now + 60).contains($0) ? $0 : nil }
        refreshLidPage(pending.last == "page" ? live : nil, now: now)
        if live != nil || (previewDeadline ?? .infinity) <= now { previewDeadline = nil }
        let deadline = live ?? previewDeadline
        countdown.isHidden = deadline == nil
        cancel.isHidden = deadline == nil
        cancel.title = previewDeadline == nil ? "Cancel Pending Action" : "Cancel Preview"

        if let deadline {
            let seconds = max(0, Int(ceil(deadline - now)))
            statusItem.button?.title = "\(seconds)s"
            countdown.title = previewDeadline == nil ? "Lid Action in \(seconds)s" : "Preview · \(seconds)s"
            if timer == nil {
                let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                    self?.refreshCountdown()
                }
                RunLoop.main.add(timer, forMode: .common)
                RunLoop.main.add(timer, forMode: .eventTracking)
                self.timer = timer
            }
        } else {
            statusItem.button?.title = ""
            timer?.invalidate()
            timer = nil
        }
    }

    private func refreshLidPage(_ deadline: TimeInterval?, now: TimeInterval) {
        if deadline != pageDeadline {
            pageDeadline = deadline
            livePage?.close()
            livePage = nil
        }
        guard let deadline else { return }
        let seconds = max(0, Int(ceil(deadline - now)))
        if livePage == nil, seconds > 0, let url = configuredPageURL,
           let page = LidPage(url: url, cancel: { [weak self] in self?.update(["cancel"]) }) {
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
            self.refreshCountdown()
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
        previewDeadline = Date().timeIntervalSince1970 + 5
        refreshCountdown()
    }

    @objc private func cancelCountdown() {
        if previewDeadline != nil {
            previewDeadline = nil
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

    @objc private func setMode(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { update(["mode", value]) }
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { update(["delay", value]) }
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

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
enum LidkillApp {
    @MainActor static func main() {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != getpid() }) { return }

        let application = NSApplication.shared
        let menuBar = MenuBar()
        application.delegate = menuBar
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(menuBar) { application.run() }
    }
}
