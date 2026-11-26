import AppKit

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
