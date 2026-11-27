import AppKit

final class MenuBar: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let cli = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/lidkill")
    private let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lidkill", isDirectory: true)
    private let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/lidkill.log")
    private let commandQueue = DispatchQueue(label: "com.lidkill.menubar.commands")
    let menu = NSMenu()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var showControlsWhenReady = false
    private var controlsReady = false
    private(set) var controlsWindow: NSWindow?
    var hasVisibleStatusItem: Bool { statusItem.isVisible && statusItem.button != nil && statusItem.menu === menu }
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
    private var skipItem: NSMenuItem!
    private var reopenItem: NSMenuItem!
    private var pageItem: NSMenuItem!
    private var previewWebsite: NSMenuItem!
    private var testWebsite: NSMenuItem!
    private var clearWebsite: NSMenuItem!
    private var presetItem: NSMenuItem!
    private var whenItem: NSMenuItem!
    private var externalItem: NSMenuItem!
    private var notifyItem: NSMenuItem!
    private var armForItem: NSMenuItem!
    private var iconHidden = false
    private var iconReason = "ok"
    private var timerLeft = 0
    private var iconProbeTimer: Timer?

    private var pageURLFile: URL { configDirectory.appendingPathComponent("page-url") }
    private var configuredPageURL: URL? {
        (try? String(contentsOf: pageURLFile, encoding: .utf8)).flatMap(LidPage.websiteURL)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A saved position from an older build can park the icon where the notch hides it.
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("NSStatusItem") && key.contains("Lidkill") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if let icon = MenuBar.makeGlyph() {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Lidkill")
        }
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        statusItem.button?.setAccessibilityLabel("Lidkill")
        statusItem.button?.toolTip = "Lidkill"
        statusItem.behavior = []
        statusItem.isVisible = true
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
        armForItem = add("Arm For", to: menu)
        armForItem.submenu = choices(
            [("1 Hour", "1h"), ("4 Hours", "4h"), ("8 Hours", "8h")], action: #selector(armFor(_:))
        )
        skipItem = add("Skip Next Lid Close", to: menu, action: #selector(toggleSkip))
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
        whenItem = add("Only When", to: menu)
        whenItem.submenu = choices(
            [("Any Power Source", "any"), ("On Battery", "battery"), ("On AC Power", "ac")],
            action: #selector(setWhen(_:))
        )
        externalItem = add("Ignore With External Display", to: menu, action: #selector(toggleExternal))
        notifyItem = add("Notify Before Action", to: menu, action: #selector(toggleNotify))
        presetItem = add("Presets", to: menu)
        presetItem.submenu = choices(
            [("Safe · 5s With Notice", "safe"), ("Desk · Ignore External Display", "desk"),
             ("Guard · Instant Hard Shutdown", "guard"), ("Battery Only", "battery")],
            action: #selector(applyPreset(_:))
        )
        let pageMenu = NSMenu()
        pageMenu.autoenablesItems = false
        pageItem = add("Lid Page", to: menu)
        pageItem.submenu = pageMenu
        pageItem.isEnabled = true
        _ = add("Set Website…", to: pageMenu, action: #selector(setWebsite))
        reopenItem = add("Cancel on Reopen", to: pageMenu, action: #selector(toggleReopen))
        previewWebsite = add("Preview Website", to: pageMenu, action: #selector(showWebsitePreview))
        testWebsite = add("Test Countdown With Website", to: pageMenu, action: #selector(testWebsiteCountdown))
        clearWebsite = add("Disable Lid Page", to: pageMenu, action: #selector(disableWebsite))
        menu.addItem(.separator())
        loginItem = add("Launch at Sign-In", to: menu, action: #selector(toggleLogin))
        _ = add("Preview Countdown", to: menu, action: #selector(preview))
        _ = add("Setup Status…", to: menu, action: #selector(showSetupStatus))
        _ = add("Open Log", to: menu, action: #selector(openLog))
        _ = add("Copy Diagnostic Report", to: menu, action: #selector(copyReport))
        for control in [arm, armForItem, dryRunItem, modeItem, delayItem, loginItem, skipItem, reopenItem,
                        whenItem, externalItem, notifyItem, presetItem] {
            control?.isEnabled = false
        }
        scheduleIconProbes()

        observeCountdown()
        reloadCountdown()
        refreshSettings()
        if showControlsWhenReady { showControls() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.absoluteString == "lidkill://controls" }) else { return }
        if headline == nil {
            showControlsWhenReady = true
        } else {
            showControls()
        }
    }

    private func showControls() {
        if controlsWindow == nil {
            let frame = NSRect(x: 0, y: 0, width: 300, height: 214)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Lidkill Controls"
            window.isReleasedWhenClosed = false
            let note = NSTextField(wrappingLabelWithString: "")
            note.frame = NSRect(x: 20, y: 140, width: 260, height: 58)
            note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            note.identifier = NSUserInterfaceItemIdentifier("note")
            window.contentView?.addSubview(note)
            let first = NSButton(title: "Open Lidkill Menu ▾", target: self, action: #selector(openControlsMenu(_:)))
            let buttons = [first,
                           NSButton(title: "Setup Status…", target: self, action: #selector(showSetupStatus)),
                           NSButton(title: "Copy Diagnostic Report", target: self, action: #selector(copyReport))]
            for (index, button) in buttons.enumerated() {
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 30, y: 96 - index * 38, width: 240, height: 32)
                window.contentView?.addSubview(button)
            }
            window.initialFirstResponder = first
            window.center()
            controlsWindow = window
        }
        let note = controlsWindow?.contentView?.subviews.first {
            $0.identifier == NSUserInterfaceItemIdentifier("note")
        } as? NSTextField
        note?.stringValue = iconHidden
            ? "The menu bar icon is hidden (\(iconReason)). Use these controls or the Dock icon. To restore the icon, free some menu bar space, then run: lidkill menu"
            : "Lidkill lives in the menu bar. This window opens the same menu."
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if headline != nil { showControls() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dock = NSMenu()
        for (title, action) in [("Open Lidkill Controls", #selector(showControlsAction)),
                                (armed ? "Disarm…" : "Arm…", #selector(toggleArmed)),
                                ("Setup Status…", #selector(showSetupStatus)),
                                ("Copy Diagnostic Report", #selector(copyReport))] {
            _ = add(title, to: dock, action: action)
        }
        return dock
    }

    @objc private func showControlsAction() { showControls() }

    // MARK: menu bar icon

    /// Black-on-white artwork -> template image whose alpha is the ink. Independent of
    /// CGImage color masking, which behaved differently across macOS releases.
    static func makeGlyph(url: URL? = Bundle.main.url(forResource: "Lidkill", withExtension: "png")) -> NSImage? {
        guard let url, let asset = NSImage(contentsOf: url),
              let source = asset.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 34
        let space = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var ink = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luma = (Int(pixels[i]) * 77 + Int(pixels[i + 1]) * 150 + Int(pixels[i + 2]) * 29) >> 8
            let alpha = UInt8(255 - luma)
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = alpha
            if alpha > 40 { ink += 1 }
        }
        // Reject blank or solid results so a bad asset falls back to the system symbol.
        guard ink > 8, ink < side * side * 3 / 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let glyph = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let icon = NSImage(cgImage: glyph, size: NSSize(width: 17, height: 17))
        icon.isTemplate = true
        return icon
    }

    /// Is the status item really on screen? A full menu bar on a notched Mac hides it.
    private func probeStatusItem() -> (visible: Bool, reason: String, frame: NSRect?) {
        guard statusItem.isVisible, let window = statusItem.button?.window else {
            return (false, "macOS gave the status item no window", nil)
        }
        let frame = window.frame
        if ProcessInfo.processInfo.environment["LIDKILL_FAKE_HIDDEN"] != nil { return (false, "simulated for testing", frame) }
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            return (false, "the icon is not on any display", frame)
        }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notch = NSRect(x: left.maxX, y: frame.minY, width: max(0, right.minX - left.maxX), height: frame.height)
            if frame.intersects(notch.insetBy(dx: 1, dy: 0)) { return (false, "behind the notch", frame) }
            // Status items live right of the notch; the left side belongs to the app menus.
            if frame.midX < right.minX { return (false, "left of the notch", frame) }
        }
        if frame.maxX > screen.frame.maxX + 1 || frame.minX < screen.frame.minX - 1 || !window.isVisible {
            return (false, "pushed off the menu bar", frame)
        }
        // occlusionState is deliberately not used: it reads "hidden" while the display sleeps or locks.
        return (true, "ok", frame)
    }

    private func scheduleIconProbes() {
        for delay in [1.5, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkIcon() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.checkIcon() }
        }
    }

    private func checkIcon() {
        let probe = probeStatusItem()
        iconReason = probe.reason
        if !probe.visible && !iconHidden {
            iconHidden = true
            NSApp.setActivationPolicy(.regular)
            if let url = Bundle.main.url(forResource: "Lidkill", withExtension: "png"),
               let image = NSImage(contentsOf: url) { NSApp.applicationIconImage = image }
            showControls()
        } else if probe.visible && iconHidden {
            iconHidden = false
            NSApp.setActivationPolicy(.accessory)
        }
        // While the icon is hidden keep looking: the user may free some bar space.
        if iconHidden, iconProbeTimer == nil {
            iconProbeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.checkIcon()
            }
        } else if !iconHidden {
            iconProbeTimer?.invalidate()
            iconProbeTimer = nil
        }
        let f = probe.frame
        let lines = [
            "pid=\(getpid())",
            "icon=\(probe.visible ? "visible" : "hidden")",
            "reason=\(probe.reason)",
            "mode=\(iconHidden ? "dock" : "menu-bar")",
            "frame=\(f.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? "none")",
            "notch=\(NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } ? "yes" : "no")",
            "screens=\(NSScreen.screens.count)",
            "occlusion=\(statusItem.button?.window?.occlusionState.rawValue ?? 0)",
        ]
        try? Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: configDirectory.appendingPathComponent("menu-state"), options: .atomic)
    }

    @objc private func openControlsMenu(_ button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
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
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        let commandEnvironment = environment
        commandQueue.async {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = commandEnvironment
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
            let available = status == 0 && fields.count >= 4 && ["0", "1"].contains(fields[0])
            self.arm.isEnabled = available
            self.dryRunItem.isEnabled = available
            self.modeItem.isEnabled = available
            self.delayItem.isEnabled = available
            self.loginItem.isEnabled = available && fields.count >= 5
            self.skipItem.isEnabled = available && fields.count >= 6
            self.reopenItem.isEnabled = available && fields.count >= 7 && hasPage
            let extended = available && fields.count >= 11
            self.armForItem.isEnabled = extended && fields.first == "0"
            for item in [self.whenItem, self.externalItem, self.notifyItem, self.presetItem] {
                item?.isEnabled = extended
            }
            guard available else {
                self.headline.title = "Lidkill · CLI Unavailable"
                return
            }
            self.armed = fields[0] == "1"
            self.dryRun = fields[3] == "1"
            self.launchAtSignIn = fields.dropFirst(4).first == "1"
            if extended {
                self.timerLeft = Int(fields[10]) ?? 0
                self.externalItem.state = fields[8] == "1" ? .on : .off
                self.notifyItem.state = fields[9] == "1" ? .on : .off
                let when = String(fields[7])
                if let choices = self.whenItem.submenu?.items {
                    self.whenItem.title = "Only When · " +
                        (choices.first { $0.representedObject as? String == when }?.title ?? when)
                    for choice in choices { choice.state = choice.representedObject as? String == when ? .on : .off }
                }
            }
            let remaining = self.armed && self.timerLeft > 0 ? " · \(MenuBar.format(self.timerLeft)) left" : ""
            self.headline.title = (self.armed ? "Lidkill · Armed" : "Lidkill · Disarmed") + remaining
            self.arm.title = self.armed ? "Disarm…" : "Arm…"
            self.dryRunItem.state = self.dryRun ? .on : .off
            self.loginItem.state = self.launchAtSignIn ? .on : .off
            self.skipItem.state = fields.dropFirst(5).first == "1" ? .on : .off
            self.reopenItem.state = fields.dropFirst(6).first == "1" ? .on : .off
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
            if !self.controlsReady && fields.count >= 7 && self.hasVisibleStatusItem {
                let marker = self.configDirectory.appendingPathComponent("menu-ready")
                do {
                    try Data("\(getpid())\n".utf8).write(to: marker, options: .atomic)
                    self.controlsReady = true
                } catch {
                    NSLog("Lidkill could not record menu readiness: %@", error.localizedDescription)
                }
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

    private func openInTerminal(_ name: String) {
        guard let script = Bundle.main.url(forResource: name, withExtension: "command"),
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

    @objc private func toggleArmed() {
        guard armed else { openInTerminal("on"); return }
        // The sudoers rule installed when arming allows a prompt-free disarm.
        run(["off", "--no-prompt"]) { [weak self] status, _ in
            guard let self else { return }
            if status == 0 { self.refreshSettings(); self.reloadCountdown() } else { self.openInTerminal("off") }
        }
    }

    @objc private func armFor(_ sender: NSMenuItem) {
        if let span = sender.representedObject as? String { openInTerminal("on-" + span) }
    }

    @objc private func setWhen(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { update(["when", value]) }
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { update(["preset", value]) }
    }

    @objc private func toggleExternal() { update(["external", externalItem.state == .on ? "off" : "on"]) }

    @objc private func toggleNotify() { update(["notify", notifyItem.state == .on ? "off" : "on"]) }

    @objc private func copyReport() {
        run(["report", "--stdout"]) { [weak self] status, report in
            guard status == 0 else { self?.showMessage(report); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            self?.showMessage("The diagnostic report is on your clipboard. Paste it into your bug report. Your user name and home folder are removed.")
        }
    }

    static func format(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    @objc private func toggleDryRun() { update(["dryrun", dryRun ? "off" : "on"]) }

    @objc private func toggleLogin() { update(["login", launchAtSignIn ? "off" : "on"]) }

    @objc private func toggleSkip() { update(["skip", skipItem.state == .on ? "off" : "on"]) }

    @objc private func toggleReopen() { update(["page-reopen", reopenItem.state == .on ? "off" : "on"]) }

    @objc private func showSetupStatus() {
        run(["doctor"]) { [weak self] status, report in
            guard status == 0 else { self?.showMessage(report); return }
            let alert = NSAlert()
            alert.messageText = "Lidkill Setup Status"
            alert.informativeText = report.trimmingCharacters(in: .whitespacesAndNewlines)
            alert.addButton(withTitle: "Done")
            alert.addButton(withTitle: "Copy Report")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }
        }
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
        alert.informativeText = "The default is a hard shutdown after 25 seconds. You can change the action, delay, and reopen behavior from the menu."
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
