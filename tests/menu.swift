import AppKit

@main
enum MenuSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let menuBar = MenuBar()
        app.delegate = menuBar

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { fail("menu test timed out") }
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
