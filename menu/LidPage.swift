import AppKit
import WebKit

final class LidPage: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private final class BrowserWindow: NSWindow {
        weak var browsingView: NSView?

        override func sendEvent(_ event: NSEvent) {
            let contextClick = event.type == .rightMouseDown || event.type == .rightMouseUp ||
                ((event.type == .leftMouseDown || event.type == .leftMouseUp) && event.modifierFlags.contains(.control))
            if contextClick, let view = browsingView,
               view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { return }
            super.sendEvent(event)
        }
    }

    struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL) {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = parts.host?.lowercased(),
                  !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
            let port = parts.port ?? (scheme == "https" ? 443 : 80)
            guard (1...65535).contains(port) else { return nil }
            self.scheme = scheme
            self.host = host
            self.port = port
        }

        func permits(_ url: URL, isMainFrame: Bool) -> Bool {
            Origin(url) == self || (!isMainFrame && ["about:blank", "about:srcdoc"].contains(url.absoluteString))
        }
    }

    static func websiteURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              Origin(url) != nil else { return nil }
        return url
    }

    private let origin: Origin
    private let window: BrowserWindow
    private let webView = WKWebView()
    private let tabTitle = NSTextField(labelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let back = NSButton()
    private let forward = NSButton()
    private let countdown = NSTextField(labelWithString: "")
    private let message = NSTextField(labelWithString: "")
    private let cancel: (() -> Void)?
    private let simulation: Bool

    init?(url: URL, simulation: Bool = false, cancel: (() -> Void)? = nil) {
        guard let origin = Origin(url), let screen = NSScreen.main else { return nil }
        self.origin = origin
        self.cancel = cancel
        self.simulation = simulation
        let frame = screen.visibleFrame
        let size = cancel == nil ? NSSize(width: min(900, frame.width), height: min(640, frame.height)) : frame.size
        window = BrowserWindow(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: cancel == nil ? [.titled, .closable, .resizable] : [.titled],
                               backing: .buffered, defer: false, screen: screen)
        super.init()

        window.title = cancel == nil || simulation ? "Lidkill Website Preview" : "Lidkill"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.browsingView = webView
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if cancel == nil { window.center() } else { window.setFrame(frame, display: false) }

        let header = browserHeader(url: url)

        let content = NSView()
        window.contentView = content
        for view in [header, webView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        webView.allowsLinkPreview = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: url))
    }

    private func browserHeader(url: URL) -> NSStackView {
        let brand = NSTextField(labelWithString: "LIDKILL")
        brand.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        brand.textColor = .systemIndigo
        tabTitle.stringValue = origin.host
        tabTitle.lineBreakMode = .byTruncatingTail
        let tab = pill(containing: tabTitle, color: .controlBackgroundColor)
        tab.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true
        let tabs = NSStackView(views: [brand, tab, NSView()])
        tabs.spacing = 10
        tabs.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 4, right: 12)
        if cancel != nil {
            countdown.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            tabs.addArrangedSubview(countdown)
            let cancelTitle = simulation ? "End Preview" : "Cancel Lid Action"
            tabs.addArrangedSubview(NSButton(title: cancelTitle, target: self, action: #selector(cancelAction)))
        }

        configure(back, symbol: "chevron.left", label: "Back", action: #selector(goBack))
        configure(forward, symbol: "chevron.right", label: "Forward", action: #selector(goForward))
        let reload = NSButton()
        configure(reload, symbol: "arrow.clockwise", label: "Reload Website", action: #selector(reloadPage))
        updateHistory()

        let secure = origin.scheme == "https"
        let indicator = NSImageView(image: NSImage(systemSymbolName: secure ? "lock.fill" : "lock.open",
                                                   accessibilityDescription: secure ? "HTTPS" : "Unencrypted HTTP") ?? NSImage())
        indicator.contentTintColor = secure ? .systemIndigo : .systemOrange
        address.stringValue = url.absoluteString
        address.lineBreakMode = .byTruncatingTail
        address.setAccessibilityLabel("Read-only website address")
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let location = NSStackView(views: [indicator, address])
        location.spacing = 6
        let toolbar = NSStackView(views: [back, forward, reload, pill(containing: location, color: .windowBackgroundColor)])
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)

        message.textColor = .secondaryLabelColor
        message.lineBreakMode = .byTruncatingTail
        message.isHidden = true
        let status = NSStackView(views: [message])
        status.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let header = NSStackView(views: [tabs, toolbar, status])
        header.orientation = .vertical
        header.spacing = 0
        header.alignment = .leading
        tabs.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        toolbar.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        status.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        return header
    }

    private func pill(containing view: NSView, color: NSColor) -> NSStackView {
        let pill = NSStackView(views: [view])
        pill.edgeInsets = NSEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.layer?.backgroundColor = color.cgColor
        return pill
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func updateHistory() {
        back.isEnabled = webView.canGoBack
        forward.isEnabled = webView.canGoForward
    }

    private func showMessage(_ text: String) {
        message.stringValue = text
        message.isHidden = text.isEmpty
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) { webView.stopLoading() }

    func updateCountdown(_ seconds: Int) {
        countdown.stringValue = simulation ? "Preview · \(seconds)s" : "\(seconds)s remaining"
    }

    @objc private func cancelAction() { cancel?() }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadPage() { webView.reload() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url, origin.permits(url, isMainFrame: true) {
            address.stringValue = url.absoluteString
        }
        tabTitle.stringValue = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? origin.host
        updateHistory()
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !action.shouldPerformDownload, let frame = action.targetFrame, let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed = origin.permits(url, isMainFrame: frame.isMainFrame)
        if frame.isMainFrame {
            showMessage(allowed ? "" : "Link outside the configured site blocked.")
        }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let attachment = disposition?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "attachment"
        let allowed = response.response.url.map { origin.permits($0, isMainFrame: response.isForMainFrame) } ?? false
        if response.isForMainFrame && !allowed {
            showMessage("Redirect outside the configured site blocked.")
        }
        decisionHandler(response.canShowMIMEType && !attachment && allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled && message.stringValue.isEmpty {
            showMessage("Website failed to load.")
        }
    }
}
