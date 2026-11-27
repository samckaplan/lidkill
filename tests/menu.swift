import AppKit

@main
enum MenuSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // The icon must render from the shipped artwork, not fall back to a system symbol.
        guard let glyph = MenuBar.makeGlyph(url: URL(fileURLWithPath: "menu/Lidkill.png")), glyph.isTemplate,
              let cg = glyph.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { fail("icon did not render") }
        var clear = 0, inked = 0
        for i in stride(from: 3, to: CFDataGetLength(data), by: 4) {
            if bytes[i] < 16 { clear += 1 } else if bytes[i] > 200 { inked += 1 }
        }
        if clear < 100 || inked < 20 { fail("icon is blank or solid (clear \(clear), inked \(inked))") }
        let menuBar = MenuBar()
        app.delegate = menuBar

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fail("menu test timed out") }
        DispatchQueue.main.async {
            Task { @MainActor in
                await waitFor("visible menu and enabled controls") {
                    menuBar.hasVisibleStatusItem && menuBar.menu.item(withTitle: "Dry Run")?.isEnabled == true
                }
                guard let dryRun = menuBar.menu.item(withTitle: "Dry Run"),
                      let skip = menuBar.menu.item(withTitle: "Skip Next Lid Close") else {
                    fail("missing menu actions")
                }
                menuBar.menu.performActionForItem(at: menuBar.menu.index(of: dryRun))
                await waitFor("dry-run checkbox") { dryRun.state == .on }
                menuBar.menu.performActionForItem(at: menuBar.menu.index(of: skip))
                await waitFor("skip checkbox") { skip.state == .on }
                for title in ["Presets", "Only When", "Ignore With External Display", "Notify Before Action",
                              "Arm For", "Copy Diagnostic Report"] where menuBar.menu.item(withTitle: title) == nil
                    && !menuBar.menu.items.contains(where: { $0.title.hasPrefix(title) }) {
                    fail("missing menu item: " + title)
                }
                if ProcessInfo.processInfo.environment["LIDKILL_EXPECT_FALLBACK"] != nil {
                    // Simulated hidden icon: the Dock icon and controls window must take over.
                    await waitFor("dock fallback") { NSApp.activationPolicy() == .regular }
                    await waitFor("fallback controls window") { menuBar.controlsWindow?.isVisible == true }
                    print("Hidden-icon fallback passed.")
                    exit(0)
                }
                guard let url = URL(string: "lidkill://controls") else { fail("invalid controls URL") }
                menuBar.application(app, open: [url])
                await waitFor("controls window") { menuBar.controlsWindow?.isVisible == true }
                print("Menu bar item, settings actions, and controls window passed.")
                exit(0)
            }
        }
        withExtendedLifetime(menuBar) { app.run() }
    }

    @MainActor private static func waitFor(_ name: String, check: () -> Bool) async {
        for _ in 0..<40 {
            if check() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        fail("failed to verify " + name)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
